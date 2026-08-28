# og.nvim

Edit OpenGate artifacts — automation rules, connector functions, provision
functions, dashboards and widgets — in Neovim, against a live platform.

> **Unofficial community project.** Not an Amplía Soluciones product, not
> supported by Amplía, and provided with no warranty. It drives the
> [`og`](https://github.com/carlosprados/og-cli) CLI, which can write to a
> production OpenGate tenant. You are responsible for what you deploy.

---

## What it does, and what it deliberately does not

A thin shell over the `og` binary. Every platform interaction is a child
process: there is no HTTP, no authentication and no knowledge of OpenGate's API
in this plugin. That is the design. The moment a call is reimplemented in Lua
there are two sources of truth, and the Lua one is the one that goes stale.

**Completion and diagnostics for the JavaScript itself are not this plugin's
job, and you already have them.** `og typegen` writes `og-globals.d.ts` and
`jsconfig.json` into the artifact directory — the platform's ~450 functions,
your organization's real datastream identifiers, the rule's own parameters —
and any LSP setup with `ts_ls` or `vtsls` picks them up. That works whether or
not og.nvim is installed:

```js
entity['sensro.temperature']   // Property does not exist on type 'OGEntity'.
                               // Did you mean 'sensor.temperature'?
```

What og.nvim adds is everything around that: remote diffs, artifact-level
validation, and deploying without leaving the editor.

## Requirements

- Neovim **0.10+** (`vim.system`)
- The [`og`](https://github.com/carlosprados/og-cli) binary on `PATH`, logged in
  (`og login`)

Run `:checkhealth og` if something is not working. It checks the binary, its
version, and whether it is new enough for the diff view.

## Install

### lazy.nvim / LazyVim

```lua
{
  "carlosprados/og.nvim",
  cmd = { "OgDiff", "OgStatus", "OgValidate", "OgDeploy", "OgTypegen" },
  opts = {},
  keys = {
    { "<leader>od", "<cmd>OgDiff<cr>",     desc = "og: diff against remote" },
    { "<leader>os", "<cmd>OgStatus<cr>",   desc = "og: what deploy would change" },
    { "<leader>ov", "<cmd>OgValidate<cr>", desc = "og: validate artifact" },
    { "<leader>oD", "<cmd>OgDeploy<cr>",   desc = "og: deploy artifact" },
    { "<leader>ot", "<cmd>OgTypegen<cr>",  desc = "og: regenerate typings" },
  },
}
```

`opts = {}` is enough: with no configuration the plugin uses `og` on `PATH` and
the profile the CLI is already configured with. Adding `<leader>o` to
`which-key`'s group list is optional:

```lua
{ "folke/which-key.nvim", opts = { spec = { { "<leader>o", group = "opengate" } } } }
```

Loading is deferred until one of the commands is used, so the plugin costs
nothing on startup in a config you also use for everything else.

## Commands

| Command | What it does |
|---|---|
| `:OgDiff` | The file you are editing, side by side with its remote content, in Neovim's own diff mode. `]c`, `[c`, `do` and `dp` all work. |
| `:OgStatus [profile]` | What deploying the whole artifact would change — metadata and every code file — rendered by `og diff`. With a profile name, compares against that tenant instead (the promotion question). |
| `:OgValidate` | Runs `og <family> validate` and publishes the findings as diagnostics. Local, no credentials, milliseconds. |
| `:OgDeploy` | Shows what would change, asks, then deploys. `:OgDeploy!` skips the question. |
| `:OgTypegen` | Regenerates the editor typings for this artifact — they are datamodel-derived and go stale when the organization gains a datastream. |

Every command acts on the artifact the current buffer belongs to, found by
walking up for `rule.json`, `connectorfunction.json`, `provisionfunction.json`,
`widget.json`, `dashboard.json` or `workspace.json`. The nearest one wins, so
editing a widget acts on that widget and not on the workspace above it.

## Configuration

```lua
require("og").setup({
  bin = "og",              -- path to the binary
  org = nil,               -- only if it should differ from og's own default
  profile = nil,           -- og profile
  timeout = 30000,         -- ms before a call is abandoned

  validate_on_save = true, -- local, free, catches artifact-level mistakes
  deploy_on_save = false,  -- writes to a live platform: off unless you say so

  diagnostics = { enabled = true },
})
```

### On `deploy_on_save`

Off by default, and worth leaving off. A plugin that pushes on every `:w`
eventually pushes something you were still thinking about. If you want
deploy-on-save, `og watch` does it from a terminal with a conflict guard and a
production-profile guard, and it is a better place for it.

Do not run both at once over the same tree: two watchers produce duplicate
deploys.

## Credentials

None are stored here. Host, token, organization and profile all come from og's
own configuration (`~/.og/config.yaml`), so there is exactly one place they can
be wrong.

## Licence

Apache-2.0.
