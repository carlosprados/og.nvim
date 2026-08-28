--- `og <family> validate` as native diagnostics.
---
--- Validation is local and needs no credentials, so this is the one thing the
--- plugin can do on every write without touching the network or the platform.
--- It is not a JavaScript checker — that is tsserver's job, driven by the
--- jsconfig og typegen writes — it catches the artifact-level mistakes a type
--- checker cannot see: a declared code file that is missing, metadata that is
--- not valid JSON, a connector function that would deploy and never fire.
local artifact = require("og.artifact")
local cli = require("og.cli")
local config = require("og.config")

local M = {}

local ns = vim.api.nvim_create_namespace("og.nvim")

--- Map a finding onto the buffer it belongs to.
---
--- A finding names a file relative to the artifact directory. When that file is
--- open, the diagnostic goes there; when it is not, or when the finding is about
--- the artifact as a whole, it goes on the buffer that triggered the run — better
--- a diagnostic in a slightly wrong place than one nobody ever sees.
local function target_buf(art, finding, fallback)
  if not finding.file or finding.file == "" then
    return fallback
  end
  local path = art.dir .. "/" .. finding.file
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    return bufnr
  end
  return fallback
end

--- run validates the artifact the buffer belongs to and publishes the result.
---@param bufnr integer|nil
---@param opts table|nil {silent = boolean}
function M.run(bufnr, opts)
  opts = opts or {}
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local art = opts.silent and artifact.find(vim.api.nvim_buf_get_name(bufnr)) or artifact.current()
  if not art then
    return
  end
  -- Only the flat families have a validator; workspaces and dashboards are
  -- hierarchical and og covers them with `workspace diff` instead.
  if art.family.command == "workspace" or art.family.command == "dashboard" or art.family.command == "widget" then
    if not opts.silent then
      vim.notify(
        ("og.nvim: %s has no validator — use :OgDiff, which covers this family"):format(art.family.kind),
        vim.log.levels.INFO
      )
    end
    return
  end

  cli.run_json({ art.family.command, "validate", art.dir }, function(data, res)
    if res.code == cli.EXIT_FAILURE or data == nil then
      if not opts.silent then
        cli.notify_failure(res, "validate failed")
      end
      return
    end

    M.clear(bufnr)
    local by_buf = {}
    for _, finding in ipairs(data.findings or {}) do
      local target = target_buf(art, finding, bufnr)
      by_buf[target] = by_buf[target] or {}

      -- og keeps the file in its own field and its message reads as the
      -- continuation of it — "is missing, but the rule is in ADVANCED mode".
      -- On the file's own buffer that is right; anywhere else the message has
      -- to say what it is about, or it names nothing at all.
      local message = finding.message or ""
      if finding.file and finding.file ~= "" and target ~= vim.fn.bufnr(art.dir .. "/" .. finding.file) then
        message = ("%s %s"):format(finding.file, message)
      end

      table.insert(by_buf[target], {
        lnum = math.max((tonumber(finding.line) or 1) - 1, 0),
        col = 0,
        severity = config.options.diagnostics.severity_map[finding.severity] or vim.diagnostic.severity.WARN,
        message = message,
        source = "og",
      })
    end

    for target, items in pairs(by_buf) do
      if vim.api.nvim_buf_is_valid(target) then
        vim.diagnostic.set(ns, target, items)
      end
    end

    if not opts.silent and vim.tbl_isempty(by_buf) then
      vim.notify(("og.nvim: %s — no problems found."):format(vim.fn.fnamemodify(art.dir, ":t")), vim.log.levels.INFO)
    end
  end)
end

--- clear removes og's diagnostics from a buffer.
---@param bufnr integer|nil
function M.clear(bufnr)
  vim.diagnostic.reset(ns, bufnr)
end

return M
