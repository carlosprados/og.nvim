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

--- open shows the current buffer against its remote content in diff mode.
function M.open()
  local art = artifact.current()
  if not art then
    return
  end
  if not art.id or art.id == "" then
    vim.notify(
      ("og.nvim: %s has no identifier in %s — nothing remote to compare against"):format(
        art.family.kind,
        art.family.meta
      ),
      vim.log.levels.WARN
    )
    return
  end

  local rel = artifact.code_file(art)
  if not rel then
    vim.notify("og.nvim: this buffer is not a file inside the artifact directory", vim.log.levels.WARN)
    return
  end
  if not rel:match("%.js$") then
    vim.notify(
      ("og.nvim: %s is not a code file — :OgStatus compares the whole artifact, metadata included"):format(rel),
      vim.log.levels.INFO
    )
    return
  end

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
