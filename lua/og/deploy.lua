--- Deploying the artifact you are editing.
---
--- This is the only thing the plugin does that writes to a live platform, so it
--- is the only thing that asks first. `og watch` exists for people who want
--- deploy-on-save from a terminal; the plugin deliberately does not spawn it —
--- two watchers over the same files produce duplicate deploys, and a plugin that
--- pushes silently on :w is one bad reflex away from an incident.
local artifact = require("og.artifact")
local cli = require("og.cli")
local config = require("og.config")
local diff = require("og.diff")

local M = {}

--- run deploys the artifact the current buffer belongs to.
---@param opts table|nil {confirm = boolean}
function M.run(opts)
  opts = vim.tbl_extend("force", { confirm = true }, opts or {})

  local art = artifact.current()
  if not art then
    return
  end

  -- A widget cannot be deployed on its own: the platform has no endpoint for a
  -- grid item, so the dashboard is what goes. This is the rule `og workspace
  -- watch` already follows for a widget edit, and the confirmation below shows
  -- the dashboard's diff, so what is sent is what was agreed to.
  local target = artifact.anchor(art)
  if not target then
    return
  end
  if target.dir ~= art.dir then
    vim.notify(
      ("og.nvim: a %s deploys as its %s — %s is what will be sent."):format(
        art.family.kind,
        target.family.kind,
        vim.fn.fnamemodify(target.dir, ":t")
      ),
      vim.log.levels.INFO
    )
    art = target
  end

  local name = vim.fn.fnamemodify(art.dir, ":t")

  if not opts.confirm then
    go()
    return
  end

  -- Show what would change before asking. Deploying blind is exactly the habit
  -- the CLI's diff was written to break, and the plugin should not reintroduce
  -- it just because a keymap is quicker than a command.
  --
  cli.run({ art.family.command, "diff", art.dir }, function(res)
    local summary = vim.trim(res.stdout)
    if res.code == cli.EXIT_OK and summary == "" then
      vim.notify(("og.nvim: %s matches the platform — nothing to deploy."):format(name), vim.log.levels.INFO)
      return
    end
    if res.code == cli.EXIT_FAILURE then
      cli.notify_failure(res, "cannot read the remote artifact; not deploying")
      return
    end

    diff.show_scratch(("og deploy? — %s"):format(name), vim.split(summary, "\n", { plain = true }))
    vim.ui.select({ "no", "yes" }, {
      prompt = ("Deploy %s to the platform?"):format(name),
    }, function(choice)
      if choice == "yes" then
        go()
      end
    end)
  end)
end

--- attach installs the buffer-local autocommands for an artifact file.
---@param bufnr integer
function M.attach(bufnr)
  local group = vim.api.nvim_create_augroup(("og.nvim.buf.%d"):format(bufnr), { clear = true })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    buffer = bufnr,
    desc = "og.nvim: validate, and deploy when asked to",
    callback = function()
      if config.options.validate_on_save and config.options.diagnostics.enabled then
        require("og.diagnostics").run(bufnr, { silent = true })
      end
      if config.options.deploy_on_save then
        -- Still no confirmation prompt here: switching this on IS the consent,
        -- and prompting on every write would make it unusable.
        M.run({ confirm = false })
      end
    end,
  })
end

return M
