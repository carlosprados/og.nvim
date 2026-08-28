--- og.nvim — OpenGate artifact editing in Neovim.
---
--- A thin shell over the `og` binary. Every platform interaction is a child
--- process; there is no HTTP, no auth and no path knowledge in this plugin, and
--- that is the design rather than an omission. The binary is the single source
--- of truth, so the plugin cannot drift from the CLI, and anything og learns
--- arrives here for free.
---
--- Completion and diagnostics for the JavaScript itself are NOT this plugin's
--- job: `og typegen` writes og-globals.d.ts and jsconfig.json into the artifact
--- directory, and any LSP setup with ts_ls or vtsls picks them up. That works
--- with or without og.nvim installed.
local M = {}

local config = require("og.config")

---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  require("og.commands").register()
end

-- Re-exported so a keymap can call the plugin without knowing its layout.
function M.diff()
  require("og.diff").open()
end

function M.status(opts)
  require("og.diff").status(opts)
end

function M.validate()
  require("og.diagnostics").run()
end

function M.deploy(opts)
  require("og.deploy").run(opts)
end

function M.typegen()
  require("og.commands").typegen()
end

return M
