--- Browsing the tenant, and pulling from it.
---
--- The VS Code extension puts this in a sidebar tree. Neovim's equivalent is a
--- picker: `vim.ui.select` is what LazyVim, Telescope, fzf-lua and snacks all
--- override, so this gets the user's own fuzzy finder for free and does not
--- impose a window layout on anybody. A hand-rolled sidebar would be more code
--- and worse.
---
--- Populated entirely from `-o json`. The listing subcommand is not the same
--- word for every family — rules `search`, the others `list` — which is a CLI
--- asymmetry this module has to know about and nothing else does.
local artifact = require("og.artifact")
local auth = require("og.auth")
local cli = require("og.cli")

local M = {}

---@class og.Family
local FAMILIES = {
  { label = "Rules", command = "rules", list = "search", id_key = "identifier", meta = "rule.json" },
  { label = "Connector functions", command = "connectors", list = "list", id_key = "identifier", meta = "connectorfunction.json" },
  { label = "Provision functions", command = "provision", list = "list", id_key = "provisionProcessorId", meta = "provisionfunction.json" },
  { label = "Workspaces", command = "workspace", list = "list", id_key = "_id", meta = "workspace.json" },
}

--- describe picks the one field worth showing beside the name, per family.
local function describe(item)
  if type(item.mode) == "string" then
    -- A rule: EASY or ADVANCED decides whether it has JavaScript at all.
    return item.active == false and (item.mode .. " · inactive") or item.mode
  end
  if type(item.operationalStatus) == "string" then
    return item.operationalStatus
  end
  if type(item.owner) == "string" then
    return item.owner
  end
  return ""
end

--- local_copies maps identifier to metadata path for every pulled artifact of a
--- family below cwd.
---
--- Matched on the identifier rather than the directory name: names are not
--- unique and slugs are derived, but the identifier is what og itself matches
--- on.
local function local_copies(meta)
  local found = {}
  for _, path in ipairs(vim.fn.glob("**/" .. meta, false, true)) do
    local ok, decoded = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    end)
    if ok and type(decoded) == "table" then
      for _, key in ipairs({ "identifier", "provisionProcessorId", "_id", "i" }) do
        local value = decoded[key]
        if type(value) == "string" and value ~= "" and not found[value] then
          found[value] = path
        end
      end
    end
  end
  return found
end

--- open_artifact opens an artifact directory's code, or its metadata when it
--- has none.
local function open_artifact(meta_path)
  local dir = vim.fn.fnamemodify(meta_path, ":h")
  local code = vim.fn.glob(dir .. "/*.js", false, true)
  vim.cmd.edit(vim.fn.fnameescape(code[1] or meta_path))
end

--- pull downloads an artifact and opens it.
local function pull(family, entry)
  vim.ui.input({ prompt = "Pull into: ", default = family.command, completion = "dir" }, function(dir)
    if not dir or dir == "" then
      return
    end
    vim.notify(("og.nvim: pulling %s…"):format(entry.name), vim.log.levels.INFO)
    cli.run({ family.command, "pull", entry.id, "--dir", dir }, function(res)
      if res.code ~= cli.EXIT_OK then
        cli.notify_failure(res, ("pulling %s failed"):format(entry.name))
        return
      end
      local here = local_copies(family.meta)[entry.id]
      if here then
        open_artifact(here)
      else
        vim.notify(("og.nvim: pulled %s to %s"):format(entry.name, dir), vim.log.levels.INFO)
      end
    end)
  end)
end

--- pick_family asks which family, then lists it.
local function pick_family()
  vim.ui.select(FAMILIES, {
    prompt = "OpenGate:",
    format_item = function(f)
      return f.label
    end,
  }, function(family)
    if family then
      M.list(family)
    end
  end)
end

--- list shows one family's artifacts and acts on the chosen one.
function M.list(family)
  cli.run_json({ family.command, family.list }, function(data, res)
    if res.code ~= cli.EXIT_OK then
      cli.notify_failure(res, ("listing %s failed"):format(family.label:lower()))
      return
    end

    local items = vim.islist(data) and data or {}
    if #items == 0 then
      vim.notify(("og.nvim: no %s in this organization"):format(family.label:lower()), vim.log.levels.INFO)
      return
    end

    -- One scan for the family rather than one per artifact.
    local here = local_copies(family.meta)

    local entries = {}
    for _, item in ipairs(items) do
      local id = item[family.id_key]
      if type(id) == "string" and id ~= "" then
        table.insert(entries, {
          id = id,
          name = tostring(item.name or item.title or id),
          detail = describe(item),
          here = here[id],
        })
      end
    end
    table.sort(entries, function(a, b)
      return a.name < b.name
    end)

    vim.ui.select(entries, {
      prompt = family.label .. ":",
      format_item = function(e)
        -- What you already have is visible without opening anything.
        local mark = e.here and "● " or "  "
        return ("%s%s%s"):format(mark, e.name, e.detail ~= "" and ("  (" .. e.detail .. ")") or "")
      end,
    }, function(entry)
      if not entry then
        return
      end
      if entry.here then
        open_artifact(entry.here)
      else
        pull(family, entry)
      end
    end)
  end)
end

--- open is `:OgBrowse`: pick a family, pick an artifact, open or pull it.
function M.open()
  auth.ensure(function()
    pick_family()
  end)
end

--- pull_current re-pulls the artifact the buffer belongs to, discarding local
--- edits. Asks first, because that is what it does.
function M.pull_current()
  local art = artifact.current()
  if not art then
    return
  end
  if not art.id then
    vim.notify(("og.nvim: this %s has no identifier"):format(art.family.kind), vim.log.levels.WARN)
    return
  end
  vim.ui.select({ "Discard and re-pull", "Cancel" }, {
    prompt = ("Re-pull %s? Local changes are lost."):format(vim.fn.fnamemodify(art.dir, ":t")),
  }, function(choice)
    if choice ~= "Discard and re-pull" then
      return
    end
    auth.ensure(function()
      cli.run({ art.family.command, "pull", art.id, "--dir", vim.fn.fnamemodify(art.dir, ":h"), "--force" }, function(res)
        if res.code ~= cli.EXIT_OK then
          cli.notify_failure(res, "pull failed")
          return
        end
        vim.cmd("checktime")
        vim.notify("og.nvim: re-pulled.", vim.log.levels.INFO)
      end)
    end)
  end)
end

return M
