--- Configuration for og.nvim.
---
--- Everything here is optional. With no setup() call at all the plugin works
--- against `og` on PATH and the profile og itself is configured with, which is
--- the common case: the CLI already knows the host, the token and the
--- organization, and duplicating that here would give a second place for them
--- to disagree.
local M = {}

---@class og.Config
---@field bin string Path to the og binary.
---@field org string|nil Organization, when it should differ from og's own default.
---@field profile string|nil og profile to use.
---@field timeout integer Milliseconds before a CLI call is abandoned.
---@field validate_on_save boolean Run validate after writing an artifact file.
---@field deploy_on_save boolean Deploy after writing. Off by default, deliberately.
---@field diagnostics og.DiagnosticsConfig

---@class og.DiagnosticsConfig
---@field enabled boolean
---@field severity_map table<string, integer>

local defaults = {
  bin = "og",
  org = nil,
  profile = nil,
  timeout = 30000,

  -- Validation is local, needs no credentials and takes milliseconds, so it is
  -- on: it is the cheapest way to catch an artifact that would deploy and never
  -- fire.
  validate_on_save = true,

  -- Deploying is not. It writes to a live platform, and a plugin that pushes on
  -- every :w is a plugin that eventually pushes something you were still
  -- thinking about. Turn it on per project if you want it.
  deploy_on_save = false,

  diagnostics = {
    enabled = true,
    severity_map = {
      error = vim.diagnostic.severity.ERROR,
      warning = vim.diagnostic.severity.WARN,
      warn = vim.diagnostic.severity.WARN,
      info = vim.diagnostic.severity.INFO,
    },
  },
}

---@type og.Config
M.options = vim.deepcopy(defaults)

---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

--- Global flags every invocation carries, from the configuration.
---@return string[]
function M.global_args()
  local args = {}
  if M.options.org and M.options.org ~= "" then
    vim.list_extend(args, { "--org", M.options.org })
  end
  if M.options.profile and M.options.profile ~= "" then
    vim.list_extend(args, { "--profile", M.options.profile })
  end
  return args
end

return M
