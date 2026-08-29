--- Running the og binary.
---
--- This is the only module that knows how to reach the platform, and it does so
--- by asking the binary. There is no HTTP in this plugin and there must never
--- be: the moment a call is reimplemented in Lua there are two sources of truth
--- for auth, paths and quirks, and the Lua one will be the stale one.
---
--- Everything is asynchronous. og talks to a remote platform, and a synchronous
--- call would freeze the editor for as long as the network felt like it.
local config = require("og.config")

local M = {}

--- og's exit codes, shared by diff and validate so CI can gate on them.
M.EXIT_OK = 0
M.EXIT_DIFF = 1
M.EXIT_FAILURE = 2

---@class og.Result
---@field code integer
---@field stdout string
---@field stderr string

--- run invokes og asynchronously and calls back on the main loop.
---
--- The callback receives the raw result rather than a thrown error: exit code 1
--- means "differences found", which is og working correctly, and turning that
--- into an error would make every caller unwrap it again.
---@param args string[]
---@param cb fun(res: og.Result)
---@param env table|nil environment overlay; secrets go here, never in args
function M.run(args, cb, env)
  local bin = require("og.binary").resolve()
  if not bin then
    -- resolve has already said what is wrong and how to fix it; a second
    -- message here would be noise.
    vim.schedule(function()
      cb({ code = M.EXIT_FAILURE, stdout = "", stderr = "" })
    end)
    return
  end

  local cmd = { bin }
  vim.list_extend(cmd, config.global_args())
  vim.list_extend(cmd, args)

  -- env is an overlay, not a replacement: og still needs PATH and HOME.
  local opts = { text = true, timeout = config.options.timeout }
  if env then
    local merged = vim.fn.environ()
    for k, v in pairs(env) do
      merged[k] = v
    end
    opts.env = merged
  end

  local ok, err = pcall(vim.system, cmd, opts, function(out)
    vim.schedule(function()
      cb({ code = out.code, stdout = out.stdout or "", stderr = out.stderr or "" })
    end)
  end)

  if not ok then
    vim.schedule(function()
      cb({ code = M.EXIT_FAILURE, stdout = "", stderr = tostring(err) })
    end)
  end
end

--- run_json invokes og with -o json and unwraps the versioned envelope.
---
--- og wraps every JSON payload as {schemaVersion, kind, data}. Callers want the
--- data; the envelope is checked here so a future schema bump surfaces in one
--- place rather than as a nil field deep in a caller.
---@param args string[]
---@param cb fun(data: any|nil, res: og.Result)
function M.run_json(args, cb, env)
  local full = vim.list_extend(vim.deepcopy(args), { "-o", "json" })
  M.run(full, function(res)
    if res.stdout == "" then
      cb(nil, res)
      return
    end
    local ok, decoded = pcall(vim.json.decode, res.stdout)
    if not ok or type(decoded) ~= "table" then
      cb(nil, res)
      return
    end
    if decoded.data ~= nil then
      cb(decoded.data, res)
      return
    end
    -- Not every command is enveloped yet; hand back what was parsed rather
    -- than pretending there was nothing.
    cb(decoded, res)
  end, env)
end

--- notify reports a failed invocation, preferring og's own message.
---
--- og's errors are written for a human and usually say what to do next, so
--- passing them through beats wrapping them in a plugin-flavoured sentence.
---@param res og.Result
---@param context string
function M.notify_failure(res, context)
  local msg = vim.trim(res.stderr)
  if msg == "" then
    msg = vim.trim(res.stdout)
  end
  if msg == "" then
    -- Nothing to add: the binary could not be resolved, and that was already
    -- reported with the choices that go with it.
    return
  end
  vim.notify(("og.nvim: %s\n%s"):format(context, msg), vim.log.levels.ERROR)
end

return M
