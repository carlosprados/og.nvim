--- Remote-versus-local, using Neovim's own diff.
---
--- Two different questions, two commands:
---
---   :OgDiff    the file you are editing against its remote content, side by
---              side, in Neovim's diff mode. This is the one you want while
---              writing code.
---   :OgStatus  the whole artifact — metadata and every code file — through
---              `og diff`, which knows about canonicalization, three-way state
---              and cross-tenant comparison. Rendered by og, shown here.
---
--- Neither reimplements diffing. `og <family> show --path` provides the remote
--- side and `:diffthis` does the rest, which is why the result behaves exactly
--- like every other diff in the editor: ]c, [c, do, dp all work.
local artifact = require("og.artifact")
local cli = require("og.cli")

local M = {}

--- code_files lists the artifact's own JavaScript files, by name.
---
--- Its own: the artifact directory itself, not a widget's below it. A dashboard
--- offering its widgets' code would be answering a question nobody asked.
---@param art og.Artifact
---@return string[]
local function code_files(art)
  local names = {}
  for _, path in ipairs(vim.fn.glob(art.dir .. "/*.js", false, true)) do
    table.insert(names, vim.fn.fnamemodify(path, ":t"))
  end
  table.sort(names)
  return names
end

--- resolve_code_file decides which file the diff should show, then calls cb.
---
--- Invoked on a `.js` it is that file. Invoked on the artifact instead — on
--- rule.json, or straight from :OgBrowse — a diff still needs a file, so one is
--- resolved rather than refused. Metadata is never diffed as text; :OgStatus
--- reports it structurally, which is the right shape for it.
---
--- The flat families carry exactly one code field, so the question below never
--- comes up for them. A widget does: a list widget has one formatter per column,
--- and there is no basis for guessing which of five was meant.
---@param art og.Artifact The artifact the buffer is in.
---@param anchor og.Artifact The artifact paths are measured against.
---@param rel string
---@param cb fun(file: string)
local function resolve_code_file(art, anchor, rel, cb)
  if rel:match("%.js$") then
    cb(rel)
    return
  end

  -- Names relative to the anchor, since that is what the remote side is asked
  -- for: on a widget that is "<widget-dir>/<file>.js".
  local prefix = ""
  if anchor.dir ~= art.dir then
    prefix = art.dir:sub(#anchor.dir + 2) .. "/"
  end
  local names = vim.tbl_map(function(name)
    return prefix .. name
  end, code_files(art))
  if #names == 0 then
    vim.notify(
      ("og.nvim: this %s has no code file to diff — :OgStatus compares the whole artifact, metadata included"):format(
        art.family.kind
      ),
      vim.log.levels.INFO
    )
    return
  end
  if #names == 1 then
    cb(names[1])
    return
  end

  vim.ui.select(names, { prompt = "Compare which file against the platform?" }, function(choice)
    if choice then
      cb(choice)
    end
  end)
end

--- open shows the current buffer against its remote content in diff mode.
function M.open()
  local art = artifact.current()
  if not art then
    return
  end
  if not art.family.remote_file then
    vim.notify(
      ("og.nvim: og has no single-file view of a %s — :OgStatus compares the whole tree"):format(art.family.kind),
      vim.log.levels.INFO
    )
    return
  end

  -- A widget is read through its dashboard: `og dashboard show --path` takes the
  -- widget directory and the file, which is exactly the path the pull wrote.
  local anchor = artifact.anchor(art)
  if not anchor then
    return
  end
  if not anchor.id or anchor.id == "" then
    vim.notify(
      ("og.nvim: %s has no identifier in %s — nothing remote to compare against"):format(
        anchor.family.kind,
        anchor.family.meta
      ),
      vim.log.levels.WARN
    )
    return
  end

  local rel = artifact.code_file(anchor)
  if not rel then
    vim.notify("og.nvim: this buffer is not a file inside the artifact directory", vim.log.levels.WARN)
    return
  end
  resolve_code_file(art, anchor, rel, function(file)
    -- The local side of a diff is a file on disk, so the window has to be
    -- showing it: invoked on rule.json, the code file is opened first and the
    -- comparison happens there.
    if file ~= rel then
      vim.cmd.edit(vim.fn.fnameescape(anchor.dir .. "/" .. file))
    end
    M.compare(anchor, file)
  end)
end

--- compare puts the remote content of one file beside the current buffer.
---@param art og.Artifact
---@param rel string Path of the file relative to the artifact directory.
function M.compare(art, rel)
  local local_buf = vim.api.nvim_get_current_buf()
  local local_win = vim.api.nvim_get_current_win()

  cli.run({ art.family.command, "show", art.id, "--path", rel }, function(res)
    if res.code ~= cli.EXIT_OK then
      cli.notify_failure(res, ("cannot read the remote %s"):format(rel))
      return
    end
    if not vim.api.nvim_win_is_valid(local_win) then
      return
    end

    vim.api.nvim_set_current_win(local_win)

    -- A scratch buffer, not a file: nothing here should ever be written back,
    -- and marking it as such is what stops an absent-minded :w from creating a
    -- stray file next to the artifact.
    vim.cmd("leftabove vnew")
    local remote_buf = vim.api.nvim_get_current_buf()
    vim.bo[remote_buf].buftype = "nofile"
    vim.bo[remote_buf].bufhidden = "wipe"
    vim.bo[remote_buf].swapfile = false
    vim.api.nvim_buf_set_name(remote_buf, ("og-remote://%s/%s"):format(art.id, rel))
    vim.api.nvim_buf_set_lines(remote_buf, 0, -1, false, M.to_lines(res.stdout))
    vim.bo[remote_buf].filetype = vim.bo[local_buf].filetype
    vim.bo[remote_buf].modifiable = false
    vim.bo[remote_buf].modified = false

    vim.cmd("diffthis")
    vim.api.nvim_set_current_win(local_win)
    vim.cmd("diffthis")
  end)
end

--- status runs `og <family> diff` on the artifact and shows og's own rendering.
---
--- Deliberately og's text and not a re-render: it carries the three-way state
--- markers, the pruned tree for a workspace and the note about which fields were
--- ignored, none of which this plugin should be reproducing.
---@param opts table|nil {against = string}
function M.status(opts)
  opts = opts or {}
  local art = artifact.current()
  if not art then
    return
  end

  -- A widget has no diff of its own — it is a grid item, and the dashboard is
  -- the smallest thing og can compare or deploy — so the comparison happens one
  -- level up, and says so rather than looking like it ignored the request.
  local target = artifact.anchor(art)
  if not target then
    return
  end
  if target.dir ~= art.dir then
    vim.notify(
      ("og.nvim: comparing the %s %s — og has no diff for a single %s."):format(
        target.family.kind,
        vim.fn.fnamemodify(target.dir, ":t"),
        art.family.kind
      ),
      vim.log.levels.INFO
    )
    art = target
  end

  local args = { art.family.command, "diff", art.dir }
  if opts.against and opts.against ~= "" then
    vim.list_extend(args, { "--against", opts.against })
  end

  cli.run(args, function(res)
    if res.code == cli.EXIT_FAILURE then
      cli.notify_failure(res, "diff failed")
      return
    end
    local text = vim.trim(res.stdout)
    if text == "" then
      text = "No differences."
    end
    M.show_scratch(("og diff — %s"):format(vim.fn.fnamemodify(art.dir, ":t")), vim.split(text, "\n", { plain = true }))
  end)
end

--- to_lines splits remote content the way Neovim represents a file.
---
--- A trailing newline terminates the last line; it does not start an empty one.
--- Keeping it would put one blank line in the remote buffer that the local file
--- does not have, and every diff would open showing a change at the end of the
--- file that is not there. og writes this content unterminated today, so the
--- guard is for the day it does not.
---@param content string
---@return string[]
function M.to_lines(content)
  local lines = vim.split(content, "\n", { plain = true })
  if #lines > 1 and lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

--- show_scratch opens read-only output in a split.
---@param title string
---@param lines string[]
function M.show_scratch(title, lines)
  vim.cmd("botright new")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, title)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "diff"
  vim.api.nvim_win_set_height(0, math.min(#lines + 1, 20))
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, desc = "close" })
end

return M
