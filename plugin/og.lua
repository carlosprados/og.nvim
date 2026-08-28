-- Command stubs so :OgDiff and friends exist before the plugin is loaded.
--
-- With a lazy.nvim spec that lists `cmd = { "OgDiff", … }`, lazy.nvim creates
-- these itself and this file never runs. It exists for the other installation
-- methods, where nothing else would define them until setup() had been called.
if vim.g.loaded_og_nvim then
  return
end
vim.g.loaded_og_nvim = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("og.nvim requires Neovim 0.10 or newer", vim.log.levels.ERROR)
  return
end

for _, name in ipairs({ "OgDiff", "OgStatus", "OgValidate", "OgDeploy", "OgTypegen" }) do
  if vim.fn.exists(":" .. name) == 0 then
    vim.api.nvim_create_user_command(name, function(opts)
      -- Replace the stubs with the real commands, then run the one that was
      -- typed. Registering is idempotent, so a later setup() is harmless.
      require("og.commands").register()
      vim.cmd(("%s%s %s"):format(name, opts.bang and "!" or "", opts.args))
    end, { nargs = "?", bang = true, desc = "og.nvim (loads on first use)" })
  end
end
