# og.nvim

Write OpenGate's embedded JavaScript — automation rules, connector functions,
provision functions, dashboards and widgets — in Neovim instead of the
platform's editor, against a live tenant.

> ### Unofficial community project
>
> Not an Amplía Soluciones product, not supported by Amplía, no warranty. It
> drives the [`og`](https://github.com/carlosprados/og-cli) CLI, which **writes
> to real OpenGate tenants**. You are responsible for what you deploy.

---

## Quick start

Five minutes, and nothing to install beforehand.

### 1. Install

With [lazy.nvim](https://github.com/folke/lazy.nvim) or LazyVim:

```lua
{
  "carlosprados/og.nvim",
  cmd = {
    "OgLogin", "OgInstall", "OgBrowse", "OgPull",
    "OgDiff", "OgStatus", "OgValidate", "OgDeploy", "OgTypegen",
  },
  opts = {},
  keys = {
    { "<leader>ob", "<cmd>OgBrowse<cr>",   desc = "og: browse the platform" },
    { "<leader>od", "<cmd>OgDiff<cr>",     desc = "og: diff against remote" },
    { "<leader>os", "<cmd>OgStatus<cr>",   desc = "og: what deploy would change" },
    { "<leader>ov", "<cmd>OgValidate<cr>", desc = "og: validate artifact" },
    { "<leader>oD", "<cmd>OgDeploy<cr>",   desc = "og: deploy artifact" },
    { "<leader>ot", "<cmd>OgTypegen<cr>",  desc = "og: regenerate typings" },
  },
}
```

`opts = {}` is enough. Nothing is loaded until one of the commands is used, so
the plugin costs nothing on startup in a config you also use for everything
else. Adding `<leader>o` to `which-key`'s groups is optional:

```lua
{ "folke/which-key.nvim", opts = { spec = { { "<leader>o", group = "opengate" } } } }
```

Requires **Neovim 0.10+** (`vim.system`).

### 2. Get the binary

You do **not** need the `og` CLI already. If it is not on your `PATH`:

```vim
:OgInstall
```

It downloads the right build for your machine into `stdpath("data")`, verifies
its SHA-256 and uses that copy — nothing else on the system is touched. If you
already have og, it is used as it is; **2.4.0 or newer**, or the plugin says
which commands will not work.

### 3. Log in

```vim
:OgLogin
```

| It asks for | |
|---|---|
| **Host** | `https://api.opengate.es` unless yours is elsewhere |
| **Email** | Your OpenGate account |
| **Password** | Never echoed, never stored here — see [Logging in](#logging-in) |
| **2FA code** | Leave empty unless your account has it |

Then it asks how much access you want. Take **Everything** the first time; the
trade-off is explained in [Logging in](#logging-in).

### 4. Get something to edit

```vim
:OgBrowse
```

Pick **Rules**, then a rule. It is not on your machine yet, so you are asked
where to put it — accept the suggestion. It downloads and opens.

### 5. See it work

In the file that just opened, type a datastream identifier that does not exist:

```js
entity['this.does.not.exist']
```

It is underlined **before you deploy anything**, provided you have an LSP set
up with `ts_ls` or `vtsls`. Pulling the artifact also wrote the type
declarations for *your* organization: its real datastream identifiers and the
~450 platform functions.

Now change something real and run `:OgDiff`. You get Neovim's own diff mode —
`]c`, `[c`, `do` and `dp` all behave as they do everywhere else — with the
tenant's current version on the left.

Nothing has been deployed. `:OgDeploy` is a separate command that shows you the
diff and asks first.

---

## What this does, and what it does not

A thin shell over the `og` binary. Every platform interaction is a child
process: no HTTP, no authentication and no knowledge of OpenGate's API live in
this plugin, by design. Reimplement one call in Lua and there are two sources of
truth, and the Lua one is the one that goes stale.

**The completion does not come from this plugin**, and works with or without it.
`og typegen` writes `og-globals.d.ts` and `jsconfig.json` into each artifact
directory and any `ts_ls` or `vtsls` setup reads them — which is why step 5
works:

```js
entity['sensro.temperature']   // Property does not exist on type 'OGEntity'.
                               // Did you mean 'sensor.temperature'?
```

What this adds is everything around it: browsing, diffing, validating,
deploying and logging in without leaving the editor.

---

## Browsing the platform

`:OgBrowse` asks which family — **Rules**, **Connector functions**, **Provision
functions**, **Workspaces** — and then lists what is on your tenant. A `●`
marks what you already have locally; choosing it opens the file. Choosing
anything else asks where to pull it and opens it there.

Matching is by identifier, not by folder name: names are not unique and slugs
are derived.

The list is a plain `vim.ui.select`, which is what LazyVim, Telescope, fzf-lua
and snacks all override — so it is *your* picker, with your keymaps, and this
plugin imposes no window layout on you.

`:OgPull` re-downloads the artifact you are in, discarding local changes. It
asks first, because that is what it does.

---

## Commands

| Command | What it does |
|---|---|
| `:OgLogin` | Credentials → `og login`. Nothing stored here. |
| `:OgInstall` | Download the og CLI for this plugin, checksum-verified. |
| `:OgBrowse` | List the tenant and open or pull an artifact. |
| `:OgPull` | Re-pull this artifact, discarding local changes. Asks first. |
| `:OgDiff` | This file against its remote content, in Neovim's diff mode. Run on the artifact rather than a `.js` — on `rule.json`, or straight after `:OgBrowse` — it resolves the code file. |
| `:OgStatus [profile]` | What deploying the whole artifact would change — metadata and every code file — as `og diff` renders it. With a profile name, compares against that tenant instead: the promotion question rather than the drift one. |
| `:OgValidate` | `og <family> validate`, published as diagnostics. Local, no credentials, milliseconds. Also runs on save. |
| `:OgDeploy` | Shows what would change, asks, then deploys. `:OgDeploy!` skips the question. |
| `:OgTypegen` | Regenerate the editor typings for this artifact — they are datamodel-derived and go stale when the organization gains a datastream. |

Every command acts on the artifact the current buffer belongs to, found by
walking up for `rule.json`, `connectorfunction.json`, `provisionfunction.json`,
`widget.json`, `dashboard.json` or `workspace.json`. The nearest one wins, so
editing a widget acts on that widget and not on the workspace above it.

### What each family supports

og itself is not uniform across families, and the plugin follows it rather than
pretending otherwise:

| | `:OgDiff` | `:OgStatus` | `:OgValidate` | `:OgDeploy` |
|---|---|---|---|---|
| Rule, connector function, provision function | yes | yes | yes | yes |
| Dashboard | yes | yes | — | yes |
| Widget | yes | as its dashboard | — | as its dashboard |
| Workspace | — | yes | — | yes |

A widget is a grid item, not something the platform can address on its own, so
the dashboard it sits in is the smallest unit og can compare or deploy. Editing
a widget still works exactly as editing a rule does — `:OgDiff` on a formatter
shows that formatter — but `:OgStatus` and `:OgDeploy` act on the dashboard, and
say so before they do. It is the same boundary `og watch` draws.

A workspace is the one artifact with no single-file view: `:OgStatus` compares
the whole tree instead.

---

## Logging in

`og login` does the authenticating; this plugin only collects what it asks for.
The token goes into og's own profile (`~/.og/config.yaml`, created at mode 0600
if absent) and **no password is stored anywhere**. The password is read with
`inputsecret` so it is never echoed and never enters your command history, and
it reaches og through the environment rather than the command line, because
arguments are readable by anything that can list processes.

**Why it asks how much access you want.** OpenGate allows one web session per
user. The Web API sign-in that workspaces and dashboards need can therefore
evict your browser session on the same account, repeatedly. Declining it covers
rules, connector functions and provision functions and leaves your browser
alone. A dedicated account for the CLI avoids the question entirely.

Commands that need the platform check the session **before** doing the work,
not after failing: `og whoami` reads the token's own claims locally, so it costs
a process and no request. If there is no session, or it expired, you are told
which and offered a login.

Host, token, organization and profile all come from og's own configuration, so
there is exactly one place they can be wrong.

---

## Configuration

```lua
require("og").setup({
  bin = "og",              -- path to the binary
  org = nil,               -- only if it should differ from og's own default
  profile = nil,           -- og profile, for working against more than one tenant
  timeout = 30000,         -- ms before a call is abandoned

  validate_on_save = true, -- local, free, catches artifact-level mistakes
  deploy_on_save = false,  -- writes to a live platform: off unless you say so

  diagnostics = { enabled = true },
})
```

### On `deploy_on_save`

Off by default, and worth leaving off. A plugin that pushes on every `:w`
eventually pushes something you were still thinking about.

If you want deploy-on-save, `og watch` does it from a terminal with a conflict
guard and a production-profile guard, and is a better place for it. Do not run
both over the same tree: two watchers produce duplicate deploys.

---

## Troubleshooting

`:checkhealth og` answers most of these directly: it reports the Neovim
version, whether the binary is found and runs, whether it is new enough for
`:OgDiff` and for the session check, who you are logged in as, and whether
`deploy_on_save` is on.

| What you see | What it means |
|---|---|
| *you are not logged in* / *your session expired* | Take **Log in**. The difference matters: one means you never did, the other that it lapsed |
| `HTTP 401: Unauthorized` | A session the platform rejected. `:OgLogin` |
| *the og CLI was not found* | No `og` on `PATH`. Run `:OgInstall`, or set `bin` in `setup()` |
| *older than 2.4.0* | Your og predates `dashboard show`/`dashboard diff`, so widgets are not editable. `:OgInstall` fetches a newer one |
| *this file is not inside an artifact directory* | Nothing above the file holds a family's metadata. `:OgBrowse` and pull one |
| *og has no single-file view of a workspace* | Correct: use `:OgStatus`, which compares the whole tree |
| No completion in a `.js` | That artifact has no `og-globals.d.ts` (`:OgTypegen`), or no LSP is attached to it |
| A diff opens empty | Usually an og too old for `show --path` |

---

## Related

- [`og-cli`](https://github.com/carlosprados/og-cli) — the binary this drives, and the full command reference
- [`og-vscode`](https://github.com/carlosprados/og-vscode) — the same idea for VS Code

## Licence

Apache-2.0.
