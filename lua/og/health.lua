--- :checkhealth og
---
--- The failures this plugin can produce are nearly all environmental — no
--- binary, no login, a binary too old for a command — and each has a different
--- fix. Reporting them here beats surfacing them as a confusing error at the
--- moment someone tries to deploy.
local config = require("og.config")

local M = {}

local function versioned()
  local out = vim.system({ config.options.bin, "version" }, { text = true }):wait()
  if out.code ~= 0 then
    return nil
  end
  return vim.trim(out.stdout or "")
end

function M.check()
  vim.health.start("og.nvim")

  if vim.fn.has("nvim-0.10") ~= 1 then
    vim.health.error("Neovim 0.10 or newer is required (vim.system).")
    return
  end
  vim.health.ok("Neovim " .. tostring(vim.version()))

  local bin = config.options.bin
  if vim.fn.executable(bin) ~= 1 then
    vim.health.error(("`%s` not found"):format(bin), {
      "Install og: https://github.com/carlosprados/og-cli",
      'Or point the plugin at it: require("og").setup({ bin = "/path/to/og" })',
    })
    return
  end

  local version = versioned()
  if not version then
    vim.health.error(("`%s version` failed — is it really the og binary?"):format(bin))
    return
  end
  vim.health.ok("og found: " .. version:gsub("\n.*", ""))

  -- The two newest things the plugin needs, so their absence is the useful
  -- signal that the binary is too old for a specific feature.
  if vim.system({ bin, "rules", "show", "--help" }, { text = true }):wait().code ~= 0 then
    vim.health.warn("this og has no `rules show` — :OgDiff will not work", { "Run :OgInstall." })
  else
    vim.health.ok("`og rules show --path` is available (the remote side of :OgDiff)")
  end

  if vim.system({ bin, "whoami", "--help" }, { text = true }):wait().code ~= 0 then
    vim.health.warn("this og has no `whoami` — the session is not checked before work", { "Run :OgInstall." })
  else
    vim.health.ok("`og whoami` is available (the session check)")
    local who = vim.system({ bin, "whoami" }, { text = true }):wait()
    if who.code == 0 then
      vim.health.ok("logged in: " .. vim.trim((who.stdout or ""):match("^[^\n]*") or ""))
    else
      vim.health.warn("not logged in", { "Run :OgLogin." })
    end
  end

  vim.health.info("Credentials, host and organization come from og's own profile; this plugin stores none.")
  if config.options.deploy_on_save then
    vim.health.warn("deploy_on_save is ON — every :w writes to the platform")
  end
end

return M
