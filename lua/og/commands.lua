--- User commands and the autocommand that attaches them.
---
--- Commands are registered from setup() rather than from plugin/, so a lazy.nvim
--- spec can defer loading until one of them is actually used. plugin/og.lua only
--- creates the stubs that trigger that load.
local artifact = require("og.artifact")
local cli = require("og.cli")

local M = {}

local registered = false

function M.register()
  if registered then
    return
  end
  registered = true

  local cmd = vim.api.nvim_create_user_command

  cmd("OgDiff", function()
    require("og.diff").open()
  end, { desc = "og: diff this file against its remote content" })

  cmd("OgStatus", function(opts)
    require("og.diff").status({ against = opts.args })
  end, {
    nargs = "?",
    desc = "og: what deploying this artifact would change (optionally --against a profile)",
  })

  cmd("OgValidate", function()
    require("og.diagnostics").run()
  end, { desc = "og: validate this artifact into the diagnostics list" })

  cmd("OgDeploy", function(opts)
    require("og.deploy").run({ confirm = opts.bang ~= true })
  end, { bang = true, desc = "og: deploy this artifact (! skips the confirmation)" })

  cmd("OgTypegen", function()
    M.typegen()
  end, { desc = "og: regenerate the editor typings for this artifact" })

  -- Attaching per buffer rather than globally keeps the save hook off every
  -- other JavaScript file in the machine.
  local group = vim.api.nvim_create_augroup("og.nvim", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    pattern = { "*.js", "*.json" },
    desc = "og.nvim: attach inside artifact directories",
    callback = function(args)
      if artifact.find(args.file) then
        require("og.deploy").attach(args.buf)
      end
    end,
  })
end

--- typegen regenerates og-globals.d.ts and jsconfig.json for this artifact.
---
--- Worth a command because the typings are datamodel-derived: they go stale when
--- the organization gains a datastream, and nothing in the editor would say so.
function M.typegen()
  local art = artifact.current()
  if not art then
    return
  end
  cli.run({ "typegen", "--out", art.dir }, function(res)
    if res.code ~= cli.EXIT_OK then
      cli.notify_failure(res, "typegen failed")
      return
    end
    vim.notify("og.nvim: " .. vim.trim(res.stdout), vim.log.levels.INFO)
    -- tsserver holds the old declarations until the file is re-read.
    vim.cmd("checktime")
  end)
end

return M
