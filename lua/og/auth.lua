--- Logging in, and knowing whether you are.
---
--- The plugin stores no credentials and implements no authentication. It
--- collects what `og login` asks for and hands it over; og writes the token into
--- its own profile, with its own permissions, in the one place it already lives.
--- Anything else would give the platform two places to be logged in and one of
--- them would be wrong.
local cli = require("og.cli")
local config = require("og.config")

local M = {}

--- session asks og what session it holds, or nil when og cannot say.
---
--- `og whoami` reads the token's own claims: local, instant, no request. Cheap
--- enough to call before doing work rather than discovering the answer from a
--- 401 afterwards.
---
--- nil means the question could not be asked — an og too old to have whoami, or
--- no binary. That is not the same as "not logged in", and callers must not
--- treat it as such.
---@param cb fun(session: table|nil)
function M.session(cb)
  cli.run_json({ "whoami" }, function(data, res)
    -- Exit 1 is a real answer — no session — not a failure. Only a missing
    -- command or an unparseable payload leaves the question unanswered.
    if not data or (res.code ~= cli.EXIT_OK and res.code ~= cli.EXIT_DIFF) then
      cb(nil)
      return
    end
    cb(data)
  end)
end

--- ensure runs cb only when there is a usable session, offering a login when
--- there is not.
---
--- Silent when everything is in order, and silent too when og cannot answer: an
--- older binary should degrade to finding out from the failure, not be blocked
--- by a check it cannot perform.
---@param cb fun()
function M.ensure(cb)
  M.session(function(s)
    if not s or s.loggedIn then
      cb()
      return
    end
    -- "You never logged in" and "your session lapsed" need different things
    -- from the person reading them, and a 401 collapses both.
    local reason = s.expired and ("og.nvim: your session expired%s."):format(s.user and (" (" .. s.user .. ")") or "")
      or "og.nvim: you are not logged in."
    vim.ui.select({ "Log in", "Cancel" }, { prompt = reason }, function(choice)
      if choice == "Log in" then
        M.login(cb)
      end
    end)
  end)
end

--- ask prompts for one value, returning nil when cancelled.
local function ask(opts, cb)
  vim.ui.input(opts, function(value)
    if value == nil or value == "" then
      cb(nil)
      return
    end
    cb(value)
  end)
end

--- login collects credentials and runs `og login`.
---
--- The password goes through the environment, never the argument list:
--- arguments are visible to anything that can read the process list, which on a
--- shared or managed machine is not nobody.
---@param cb fun()|nil called when the login succeeded
function M.login(cb)
  ask({ prompt = "OpenGate host: ", default = "https://api.opengate.es" }, function(host)
    if not host then
      return
    end
    ask({ prompt = "Email: " }, function(email)
      if not email then
        return
      end
      -- vim.fn.inputsecret rather than vim.ui.input: the latter has no way to
      -- mask, and a password echoed into the command line ends up in history.
      local password = vim.fn.inputsecret("Password: ")
      if password == "" then
        return
      end
      local code = vim.fn.input("2FA code (empty if none): ")

      M.run_login(host, email, password, code, cb)
    end)
  end)
end

--- run_login is the invocation itself, separated so the prompts above stay
--- readable and so a caller with credentials already in hand can skip them.
function M.run_login(host, email, password, code, cb)
  -- OpenGate allows one web session per user, and og signs in to the Web API as
  -- well by default. With a browser open on the same account that evicts it.
  -- Workspaces and dashboards need that token, so the trade is real and belongs
  -- to the person making it rather than to a default they never saw.
  vim.ui.select({
    "Everything (workspaces and dashboards; may evict your browser session)",
    "Leave my browser session alone (rules, connector functions, provision functions)",
  }, { prompt = "How much access?" }, function(choice)
    if not choice then
      return
    end

    local args = { "login", "--email", email }
    if choice:match("^Leave") then
      table.insert(args, "--no-web")
    end
    if code and code ~= "" then
      vim.list_extend(args, { "--2fa-code", code })
    end
    if config.options.profile and config.options.profile ~= "" then
      vim.list_extend(args, { "--profile", config.options.profile })
    end

    vim.notify("og.nvim: logging in…", vim.log.levels.INFO)
    -- `og login` has no --host: the host comes from the profile, and OG_HOST
    -- overrides it. Checked against the binary rather than assumed.
    cli.run(args, function(res)
      if res.code ~= cli.EXIT_OK then
        cli.notify_failure(res, "login failed")
        return
      end
      vim.notify(("og.nvim: logged in as %s."):format(email), vim.log.levels.INFO)
      if cb then
        cb()
      end
    end, { OG_PASSWORD = password, OG_HOST = host })
  end)
end

return M
