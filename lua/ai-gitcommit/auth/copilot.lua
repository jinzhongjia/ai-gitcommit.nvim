local uv = vim.uv

local M = {}

local GITHUB_DEVICE_CODE_URL = "https://github.com/login/device/code"
local GITHUB_ACCESS_TOKEN_URL = "https://github.com/login/oauth/access_token"
local COPILOT_TOKEN_URL = "https://api.github.com/copilot_internal/v2/token"
local CLIENT_ID = "Iv1.b507a08c87ecfe98"

local function get_token_path()
	return vim.fn.expand("~/.config/github-copilot/hosts.json")
end

---@param args string[]
---@param callback fun(stdout: string, code: integer)
local function curl(args, callback)
	local stdout_pipe = uv.new_pipe()
	local stdout_chunks = {}

	local handle = uv.spawn("curl", {
		args = args,
		stdio = { nil, stdout_pipe, nil },
	}, function(code)
		stdout_pipe:close()
		local stdout = table.concat(stdout_chunks, "")
		vim.schedule(function()
			callback(stdout, code)
		end)
	end)

	if not handle then
		vim.schedule(function()
			callback("", 1)
		end)
		return
	end

	stdout_pipe:read_start(function(err, data)
		if data then
			table.insert(stdout_chunks, data)
		end
	end)
end

---@return boolean
function M.is_authenticated()
	local token_path = get_token_path()
	local stat = uv.fs_stat(token_path)
	if not stat then
		return false
	end

	local fd = uv.fs_open(token_path, "r", 438)
	if not fd then
		return false
	end

	local content = uv.fs_read(fd, stat.size, 0)
	uv.fs_close(fd)

	if not content then
		return false
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok or not data["github.com"] then
		return false
	end

	return data["github.com"].oauth_token ~= nil
end

---@param oauth_token string
---@param callback fun(data: table?, err: string?)
local function get_copilot_token(oauth_token, callback)
	curl({
		"-s",
		"-H",
		"Authorization: token " .. oauth_token,
		"-H",
		"Accept: application/json",
		COPILOT_TOKEN_URL,
	}, function(stdout, code)
		if code ~= 0 then
			callback(nil, "Failed to get Copilot token")
			return
		end

		local ok, data = pcall(vim.json.decode, stdout)
		if not ok or not data.token then
			callback(nil, "Invalid Copilot token response")
			return
		end

		callback({
			token = data.token,
			expires_at = data.expires_at,
		})
	end)
end

---@param callback fun(data: table?, err: string?)
function M.get_token(callback)
	if not M.is_authenticated() then
		callback(nil, "Not authenticated. Run :AICommit login copilot")
		return
	end

	local token_path = get_token_path()
	local stat = uv.fs_stat(token_path)
	local fd = uv.fs_open(token_path, "r", 438)
	local content = uv.fs_read(fd, stat.size, 0)
	uv.fs_close(fd)

	local data = vim.json.decode(content)
	local oauth_token = data["github.com"].oauth_token

	get_copilot_token(oauth_token, callback)
end

---@param oauth_token string
local function store_token(oauth_token)
	local config_dir = vim.fn.expand("~/.config/github-copilot")
	vim.fn.mkdir(config_dir, "p")

	local token_path = get_token_path()
	local data = {
		["github.com"] = {
			oauth_token = oauth_token,
		},
	}

	local fd = uv.fs_open(token_path, "w", 384)
	if fd then
		uv.fs_write(fd, vim.json.encode(data))
		uv.fs_close(fd)
	end
end

---@param device_code string
---@param interval number
---@param callback fun(data: table?, err: string?)
local function poll_for_token(device_code, interval, callback)
	local poll_count = 0
	local max_polls = 60

	local function poll()
		poll_count = poll_count + 1
		if poll_count > max_polls then
			callback(nil, "Login timed out")
			return
		end

		curl({
			"-s",
			"-X",
			"POST",
			"-H",
			"Accept: application/json",
			"-d",
			string.format(
				"client_id=%s&device_code=%s&grant_type=urn:ietf:params:oauth:grant-type:device_code",
				CLIENT_ID,
				device_code
			),
			GITHUB_ACCESS_TOKEN_URL,
		}, function(stdout, code)
			if code ~= 0 then
				vim.defer_fn(poll, interval * 1000)
				return
			end

			local ok, data = pcall(vim.json.decode, stdout)
			if not ok then
				vim.defer_fn(poll, interval * 1000)
				return
			end

			if data.error == "authorization_pending" then
				vim.defer_fn(poll, interval * 1000)
				return
			end

			if data.error == "slow_down" then
				interval = interval + 5
				vim.defer_fn(poll, interval * 1000)
				return
			end

			if data.access_token then
				store_token(data.access_token)
				vim.notify("GitHub Copilot authenticated successfully!", vim.log.levels.INFO)
				callback({ oauth_token = data.access_token })
				return
			end

			if data.error then
				callback(nil, "OAuth error: " .. data.error)
				return
			end

			vim.defer_fn(poll, interval * 1000)
		end)
	end

	poll()
end

---@param callback fun(data: table?, err: string?)
function M.login(callback)
	curl({
		"-s",
		"-X",
		"POST",
		"-H",
		"Accept: application/json",
		"-d",
		"client_id=" .. CLIENT_ID .. "&scope=read:user",
		GITHUB_DEVICE_CODE_URL,
	}, function(stdout, code)
		if code ~= 0 then
			callback(nil, "Failed to get device code")
			return
		end

		local ok, data = pcall(vim.json.decode, stdout)
		if not ok or not data.device_code then
			callback(nil, "Invalid device code response")
			return
		end

		local msg = string.format("Please visit: %s\nAnd enter code: %s", data.verification_uri, data.user_code)
		vim.notify(msg, vim.log.levels.INFO)

		if vim.fn.has("mac") == 1 then
			uv.spawn("open", { args = { data.verification_uri } }, function() end)
		elseif vim.fn.has("unix") == 1 then
			uv.spawn("xdg-open", { args = { data.verification_uri } }, function() end)
		end

		poll_for_token(data.device_code, data.interval or 5, callback)
	end)
end

function M.logout()
	local token_path = get_token_path()
	uv.fs_unlink(token_path)
	vim.notify("GitHub Copilot logged out", vim.log.levels.INFO)
end

return M
