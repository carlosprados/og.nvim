--- Working out which artifact a buffer belongs to.
---
--- Every command in this plugin acts on "the artifact I am editing", so this is
--- the piece the rest depends on. It mirrors what the CLI does: walk up from the
--- file until a directory holds a family's metadata file. The nearest one wins,
--- which is what makes editing a widget act on that widget rather than on the
--- workspace three levels above it.
local M = {}

---@class og.Family
---@field kind string
---@field meta string Metadata filename that marks an artifact directory.
---@field command string og subcommand for this family.
---@field id_key string Field in the metadata holding the identifier.
---@field remote_file boolean Whether one file can be read back from the platform.
---@field anchor string "self", or the kind of the enclosing artifact that addresses it remotely.

--- Ordered most specific first, so a widget directory inside a dashboard
--- resolves to the widget.
---
--- `anchor` records which artifact addresses this one on the platform, and it is
--- not always itself: a widget is a grid item rather than something the platform
--- can name, so its code is read and its changes compared through the dashboard
--- it sits in. That is og's own boundary — `og workspace watch` deploys a
--- widget edit as its dashboard — and following it here is what lets the rest of
--- this plugin stay a straight pass-through to the binary.
---
--- A workspace is the one artifact with no single-file view: `og workspace diff`
--- compares the whole tree, and there is no `og workspace show --path`.
---@type og.Family[]
M.families = {
  { kind = "widget", meta = "widget.json", command = "widget", id_key = "i", remote_file = true, anchor = "dashboard" },
  { kind = "dashboard", meta = "dashboard.json", command = "dashboard", id_key = "_id", remote_file = true, anchor = "self" },
  { kind = "rule", meta = "rule.json", command = "rules", id_key = "identifier", remote_file = true, anchor = "self" },
  { kind = "connector-function", meta = "connectorfunction.json", command = "connectors", id_key = "identifier", remote_file = true, anchor = "self" },
  { kind = "provision-function", meta = "provisionfunction.json", command = "provision", id_key = "provisionProcessorId", remote_file = true, anchor = "self" },
  { kind = "workspace", meta = "workspace.json", command = "workspace", id_key = "_id", remote_file = false, anchor = "self" },
}

---@class og.Artifact
---@field dir string Absolute path of the artifact directory.
---@field family og.Family
---@field id string|nil Identifier from the metadata, when it has one.
---@field meta table|nil Decoded metadata.

local function read_json(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    return nil
  end
  return decoded
end

--- find resolves the artifact a path belongs to, or nil.
---
--- Walks up to the filesystem root. Stopping at the current working directory
--- would fail the ordinary case of opening a file by absolute path from
--- somewhere else.
---@param path string|nil Defaults to the current buffer's file.
---@return og.Artifact|nil
function M.find(path)
  path = path or vim.api.nvim_buf_get_name(0)
  if path == nil or path == "" then
    return nil
  end

  local dir = vim.fn.fnamemodify(path, ":p")
  if vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.fnamemodify(dir, ":h")
  end

  while dir and dir ~= "" do
    for _, family in ipairs(M.families) do
      local meta_path = dir .. "/" .. family.meta
      if vim.fn.filereadable(meta_path) == 1 then
        local meta = read_json(meta_path)
        local id = nil
        if meta then
          id = meta[family.id_key]
          -- A widget's identifier lives in two places depending on how the
          -- dashboard was authored; the definition is the reliable one.
          if (id == nil or id == "") and type(meta.definition) == "table" then
            id = meta.definition.wid
          end
        end
        return { dir = dir, family = family, id = id, meta = meta }
      end
    end

    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      return nil
    end
    dir = parent
  end
  return nil
end

--- current returns the artifact for the current buffer, notifying if there is
--- none. Commands use this so the "not in an artifact" message is written once.
---@return og.Artifact|nil
function M.current()
  local artifact = M.find()
  if not artifact then
    vim.notify(
      "og.nvim: this file is not inside an artifact directory\n"
        .. "  expected one of: "
        .. table.concat(
          vim.tbl_map(function(f)
            return f.meta
          end, M.families),
          ", "
        )
        .. "\n  pull one with `og rules pull`, `og connectors pull`, `og workspace pull`, …",
      vim.log.levels.WARN
    )
    return nil
  end
  return artifact
end

--- anchor returns the artifact that addresses this one on the platform.
---
--- Itself for everything but a widget, which is addressed through the dashboard
--- it belongs to. Notifies and returns nil when that dashboard is not there,
--- because a widget directory on its own is not something og can act on.
---@param art og.Artifact
---@return og.Artifact|nil
function M.anchor(art)
  if art.family.anchor == "self" then
    return art
  end

  local target
  for _, family in ipairs(M.families) do
    if family.kind == art.family.anchor then
      target = family
      break
    end
  end
  if not target then
    return art
  end

  local dir = vim.fn.fnamemodify(art.dir, ":h")
  while dir and dir ~= "" do
    local meta_path = dir .. "/" .. target.meta
    if vim.fn.filereadable(meta_path) == 1 then
      return M.find(meta_path)
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end

  vim.notify(
    ("og.nvim: a %s is addressed through its %s, and this one is not inside a pulled %s directory"):format(
      art.family.kind,
      target.kind,
      target.kind
    ),
    vim.log.levels.WARN
  )
  return nil
end

--- code_file returns the buffer's path relative to its artifact directory.
---
--- That relative name is how og addresses a remote file, so it is what `og
--- <family> show --path` needs.
---@param artifact og.Artifact
---@param path string|nil
---@return string|nil
function M.code_file(artifact, path)
  path = vim.fn.fnamemodify(path or vim.api.nvim_buf_get_name(0), ":p")
  local prefix = artifact.dir .. "/"
  if artifact.dir:sub(-1) == "/" then
    prefix = artifact.dir
  end
  if path:sub(1, #prefix) ~= prefix then
    return nil
  end
  return path:sub(#prefix + 1)
end

return M
