--- Finding, checking and — when it is not there — fetching the og binary.
---
--- The plugin is a shell over a program the user may not have. Three ways to
--- get one, in order of how much they are the user's own choice:
---
---   1. `bin` in the configuration, when it is not the default.
---   2. `og` on PATH — what someone who already uses the CLI expects.
---   3. A copy downloaded into stdpath("data"), checksum-verified, used by this
---      plugin and nothing else.
---
--- The version is checked as well as the presence, because the failure
--- otherwise is baffling: an og older than 2.4.0 has no `dashboard show`, so a
--- widget diff opens empty, and older than 2.3.0 no `whoami`, so the session is
--- never checked and a lapsed login surfaces as a 401 instead.
local config = require("og.config")

local M = {}

--- The oldest og with everything this plugin uses.
M.MINIMUM_VERSION = "2.4.0"

local REPO = "carlosprados/og-cli"

local resolved = nil
local warned = false

--- forget drops the cached resolution, for when the setting changes.
function M.forget()
  resolved, warned = nil, false
end

local function cache_dir()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "og.nvim", "bin")
end

local function cached_path()
  return vim.fs.joinpath(cache_dir(), "og")
end

--- probe reports whether a candidate runs, and what version it claims.
---
--- Running and being parseable are two different questions, and conflating them
--- was a bug: a binary built from source prints "og dev (commit: unknown)" with
--- no version in it, and treating that as "no binary at all" told the user the
--- CLI was missing while it sat right there. It runs, so it is usable; the
--- version is only needed to warn about missing features.
---@return boolean runs, string|nil version
local function probe(bin)
  local ok, out = pcall(function()
    return vim.system({ bin, "version" }, { text = true }):wait(10000)
  end)
  if not ok or out.code ~= 0 then
    return false, nil
  end
  return true, (out.stdout or ""):match("(%d+%.%d+%.%d+)")
end

local function older_than_minimum(version)
  local function parts(v)
    local a, b, c = v:match("(%d+)%.(%d+)%.(%d+)")
    return tonumber(a), tonumber(b), tonumber(c)
  end
  local a, b, c = parts(version)
  local x, y, z = parts(M.MINIMUM_VERSION)
  if a ~= x then
    return a < x
  end
  if b ~= y then
    return b < y
  end
  return c < z
end

--- resolve returns a usable og, or nil.
---@param opts table|nil {prompt = boolean} — prompt to download when missing
---@return string|nil
function M.resolve(opts)
  opts = opts or {}
  if resolved then
    return resolved
  end

  local configured = config.options.bin
  local candidates = configured ~= "og" and { configured } or { "og", cached_path() }

  for _, candidate in ipairs(candidates) do
    local runs, version = probe(candidate)
    if runs then
      resolved = candidate
      if version and older_than_minimum(version) and not warned then
        warned = true
        vim.notify(
          ("og.nvim: og %s is older than %s. Some commands will not work.\n:OgInstall fetches a newer one.")
            :format(version, M.MINIMUM_VERSION),
          vim.log.levels.WARN
        )
      end
      return resolved
    end
  end

  if opts.prompt == false then
    return nil
  end

  vim.notify(
    "og.nvim: the og CLI was not found. This plugin drives it; it cannot do anything without one.\n"
      .. "Run :OgInstall to download it, or set bin in setup().",
    vim.log.levels.ERROR
  )
  return nil
end

--- The GoReleaser asset for this machine: og_<version>_<os>_<arch>.tar.gz
local function asset_name(version)
  local uname = vim.uv.os_uname()
  local goos = ({ Linux = "linux", Darwin = "darwin" })[uname.sysname]
  local goarch = ({ x86_64 = "amd64", arm64 = "arm64", aarch64 = "arm64" })[uname.machine]
  if not goos or not goarch then
    return nil, ("no build for %s/%s"):format(uname.sysname, uname.machine)
  end
  return ("og_%s_%s_%s.tar.gz"):format(version, goos, goarch)
end

local function curl(url, accept, out_file)
  local args = { "curl", "-fsSL", "-H", "User-Agent: og.nvim", "-H", "Accept: " .. accept }
  if out_file then
    vim.list_extend(args, { "-o", out_file })
  end
  table.insert(args, url)
  local res = vim.system(args, { text = not out_file }):wait(120000)
  if res.code ~= 0 then
    return nil, ("fetching %s failed: %s"):format(url, vim.trim(res.stderr or ""))
  end
  return out_file or (res.stdout or "")
end

--- sha256 of a file, using whichever tool the machine has.
local function sha256(path)
  for _, cmd in ipairs({ { "sha256sum", path }, { "shasum", "-a", "256", path } }) do
    if vim.fn.executable(cmd[1]) == 1 then
      local res = vim.system(cmd, { text = true }):wait(60000)
      if res.code == 0 then
        return (res.stdout or ""):match("^(%x+)")
      end
    end
  end
  return nil
end

--- install downloads the latest release, verifies its checksum and caches it.
---
--- The checksum is not decoration. This puts an executable on the machine and
--- then runs it against a production platform; taking whatever arrives over the
--- network on trust would be the wrong trade for saving twenty lines.
function M.install()
  vim.notify("og.nvim: finding the latest release…", vim.log.levels.INFO)

  local body, err = curl(("https://api.github.com/repos/%s/releases/latest"):format(REPO), "application/vnd.github+json")
  if not body then
    vim.notify("og.nvim: " .. err, vim.log.levels.ERROR)
    return
  end
  local ok, release = pcall(vim.json.decode, body)
  local version = ok and (release.tag_name or ""):gsub("^v", "") or ""
  if version == "" then
    vim.notify("og.nvim: the latest release has no tag", vim.log.levels.ERROR)
    return
  end

  local asset, why = asset_name(version)
  if not asset then
    vim.notify("og.nvim: " .. why, vim.log.levels.ERROR)
    return
  end

  local dir = cache_dir()
  vim.fn.mkdir(dir, "p")
  local archive = vim.fs.joinpath(dir, asset)
  local base = ("https://github.com/%s/releases/download/v%s"):format(REPO, version)

  vim.notify(("og.nvim: downloading %s…"):format(asset), vim.log.levels.INFO)
  local _, derr = curl(("%s/%s"):format(base, asset), "application/octet-stream", archive)
  if derr then
    vim.notify("og.nvim: " .. derr, vim.log.levels.ERROR)
    return
  end

  local checksums, cerr = curl(("%s/checksums.txt"):format(base), "text/plain")
  if not checksums then
    vim.notify("og.nvim: " .. cerr, vim.log.levels.ERROR)
    return
  end
  local expected
  for line in checksums:gmatch("[^\n]+") do
    local hash, name = line:match("^(%x+)%s+(%S+)$")
    if name == asset then
      expected = hash
    end
  end
  local actual = sha256(archive)
  if not expected or not actual or expected ~= actual then
    vim.fn.delete(archive)
    vim.notify(
      "og.nvim: checksum mismatch — refusing to install it.\n"
        .. "Install og yourself from https://github.com/" .. REPO .. "/releases and set bin in setup().",
      vim.log.levels.ERROR
    )
    return
  end

  local untar = vim.system({ "tar", "-xzf", archive, "-C", dir }):wait(120000)
  vim.fn.delete(archive)
  if untar.code ~= 0 then
    vim.notify("og.nvim: unpacking failed: " .. vim.trim(untar.stderr or ""), vim.log.levels.ERROR)
    return
  end

  local bin = cached_path()
  vim.uv.fs_chmod(bin, 493) -- 0755
  if not (probe(bin)) then
    vim.notify("og.nvim: the downloaded binary does not run", vim.log.levels.ERROR)
    return
  end

  M.forget()
  resolved = bin
  vim.notify(("og.nvim: og %s installed for this plugin."):format(version), vim.log.levels.INFO)
end

return M
