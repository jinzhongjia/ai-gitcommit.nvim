local config = require("ai-gitcommit.config")

local M = {}

local DEVICE_CODE_URL = "https://github.com/login/device/code"
local ACCESS_TOKEN_URL = "https://github.com/login/oauth/access_token"
local COPILOT_TOKEN_URL = "https://api.github.com/copilot_internal/v2/token"
local DEFAULT_CLIENT_ID = "Ov23li8tweQw6odWQebz"
local SCOPE = "read:user"
local IS_WINDOWS = vim.fn.has("win32") == 1

local function get_token_path()
	return vim.fs.joinpath(vim.fn.stdpath("data"), "ai-gitcommit", "copilot.json")
end

---@param path string
---@return string?
local function read_file(path)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end
	local lines = vim.fn.readfile(path)
	return table.concat(lines, "\n")
end

---@param path string
---@param content string
local function write_file(path, content)
	vim.fn.writefile({ content }, path)
end

---@param args string[]
---@param callback fun(stdout: string, code: integer)
local function curl(args, callback)
	local full_cmd = { "curl" }
	vim.list_extend(full_cmd, args)

	vim.system(full_cmd, { text = true }, function(obj)
		vim.schedule(function()
			callback(obj.stdout or "", obj.code)
		end)
	end)
end

local function open_browser(url)
	if vim.fn.has("mac") == 1 then
		vim.system({ "open", url }, { detach = true })
	elseif IS_WINDOWS then
		vim.system({ "cmd", "/c", "start", "", url }, { detach = true })
	else
		vim.system({ "xdg-open", url }, { detach = true })
	end
end

---@return string
local function get_client_id()
	local cfg = config.get()
	if cfg.providers and cfg.providers.copilot and cfg.providers.copilot.client_id then
		return cfg.providers.copilot.client_id
	end
	return DEFAULT_CLIENT_ID
end

---@return table?
local function read_auth_data()
	local content = read_file(get_token_path())
	if not content then
		return nil
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok or not data then
		return nil
	end

	return data
end

---@param data table
local function write_auth_data(data)
	local data_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "ai-gitcommit")
	vim.fn.mkdir(data_dir, "p")
	write_file(get_token_path(), vim.json.encode(data))
end

---@param stdout string
---@param fallback string
---@return string
local function decode_error(stdout, fallback)
	local ok, data = pcall(vim.json.decode, stdout)
	if ok and data then
		if data.error_description and data.error_description ~= "" then
			return data.error_description
		end
		if data.message and data.message ~= "" then
			return data.message
		end
		if data.error and type(data.error) == "string" and data.error ~= "" then
			return data.error
		end
	end

	local trimmed = vim.trim(stdout or "")
	if trimmed ~= "" then
		return trimmed
	end

	return fallback
end

---@param github_access_token string
---@param callback fun(data: table?, err: string?)
local function fetch_copilot_token(github_access_token, callback)
	curl({
		"-s",
		"-X",
		"GET",
		"--fail-with-body",
		"-H",
		"Accept: application/json",
		"-H",
		"User-Agent: ai-gitcommit.nvim",
		"-H",
		"Authorization: Bearer " .. github_access_token,
		COPILOT_TOKEN_URL,
	}, function(stdout, exit_code)
		if exit_code ~= 0 then
			callback(nil, decode_error(stdout, "Failed to fetch GitHub Copilot token"))
			return
		end

		local ok, data = pcall(vim.json.decode, stdout)
		if not ok or not data then
			callback(nil, "Invalid Copilot token response")
			return
		end

		if not data.token or data.token == "" then
			local msg = data.message or data.error or "No Copilot token in response"
			callback(nil, msg)
			return
		end

		callback(data, nil)
	end)
end

---@param data table?
---@return boolean
local function is_copilot_token_valid(data)
	if not data or type(data.copilot_token) ~= "string" or data.copilot_token == "" then
		return false
	end

	if type(data.copilot_expires_at) ~= "number" then
		return true
	end

	return data.copilot_expires_at > (os.time() + 30)
end

---@param data table
---@param callback fun(token_data: table?, err: string?)
local function refresh_copilot_token(data, callback)
	fetch_copilot_token(data.github_access_token, function(copilot_data, token_err)
		if token_err then
			callback(nil, token_err)
			return
		end

		local endpoint = nil
		if copilot_data.endpoints and copilot_data.endpoints.api then
			endpoint = copilot_data.endpoints.api .. "/chat/completions"
		end

		local updated = vim.tbl_extend("force", data, {
			copilot_token = copilot_data.token,
			copilot_expires_at = copilot_data.expires_at,
			copilot_refresh_in = copilot_data.refresh_in,
			copilot_endpoints = copilot_data.endpoints,
			copilot_created_at = os.time(),
		})

		write_auth_data(updated)

		callback({ token = copilot_data.token, endpoint = endpoint }, nil)
	end)
end

---@param callback fun(data: table?, err: string?)
local function fetch_device_code(callback)
	local body = "client_id=" .. vim.uri_encode(get_client_id()) .. "&scope=" .. vim.uri_encode(SCOPE)
	curl({
		"-s",
		"-X",
		"POST",
		"-H",
		"Accept: application/json",
		"-H",
		"Content-Type: application/x-www-form-urlencoded",
		"-d",
		body,
		DEVICE_CODE_URL,
	}, function(stdout, exit_code)
		if exit_code ~= 0 then
			callback(nil, decode_error(stdout, "Failed to start GitHub device flow"))
			return
		end

		local ok, data = pcall(vim.json.decode, stdout)
		if not ok or not data then
			callback(nil, "Invalid device code response")
			return
		end

		if data.error then
			callback(nil, data.error_description or data.error)
			return
		end

		if not data.device_code or not data.user_code then
			callback(nil, "No device code in response")
			return
		end

		callback(data, nil)
	end)
end

---@param device_code string
---@param interval number
---@param deadline number
---@param callback fun(data: table?, err: string?)
local function poll_access_token(device_code, interval, deadline, callback)
	if os.time() >= deadline then
		callback(nil, "Device login timed out")
		return
	end

	local body = table.concat({
		"client_id=" .. vim.uri_encode(get_client_id()),
		"device_code=" .. vim.uri_encode(device_code),
		"grant_type=" .. vim.uri_encode("urn:ietf:params:oauth:grant-type:device_code"),
	}, "&")

	curl({
		"-s",
		"-X",
		"POST",
		"-H",
		"Accept: application/json",
		"-H",
		"Content-Type: application/x-www-form-urlencoded",
		"-d",
		body,
		ACCESS_TOKEN_URL,
	}, function(stdout, exit_code)
		if exit_code ~= 0 then
			callback(nil, decode_error(stdout, "Failed to poll GitHub token"))
			return
		end

		local ok, data = pcall(vim.json.decode, stdout)
		if not ok or not data then
			callback(nil, "Invalid token polling response")
			return
		end

		if data.access_token then
			callback(data, nil)
			return
		end

		local err = data.error
		if err == "authorization_pending" then
			vim.defer_fn(function()
				poll_access_token(device_code, interval, deadline, callback)
			end, interval * 1000)
			return
		end

		if err == "slow_down" then
			vim.defer_fn(function()
				poll_access_token(device_code, interval + 5, deadline, callback)
			end, (interval + 5) * 1000)
			return
		end

		if err == "expired_token" then
			callback(nil, "Device code expired. Run :AICommit login copilot again")
			return
		end

		if err == "access_denied" then
			callback(nil, "GitHub authorization denied")
			return
		end

		callback(nil, data.error_description or err or "GitHub OAuth failed")
	end)
end

---@return boolean
function M.is_authenticated()
	local data = read_auth_data()
	return data ~= nil and type(data.github_access_token) == "string" and data.github_access_token ~= ""
end

---@param callback fun(data: table?, err: string?)
function M.get_token(callback)
	local data = read_auth_data()
	if not data or not data.github_access_token then
		callback(nil, "Not authenticated. Run :AICommit login copilot")
		return
	end

	if is_copilot_token_valid(data) then
		local endpoint = nil
		if data.copilot_endpoints and data.copilot_endpoints.api then
			endpoint = data.copilot_endpoints.api .. "/chat/completions"
		end
		callback({ token = data.copilot_token, endpoint = endpoint }, nil)
		return
	end

	refresh_copilot_token(data, callback)
end

---@param callback fun(data: table?, err: string?)
function M.login(callback)
	fetch_device_code(function(device_data, device_err)
		if device_err then
			callback(nil, device_err)
			return
		end

		local verify_uri = device_data.verification_uri or device_data.verification_uri_complete
		if not verify_uri then
			callback(nil, "Missing verification URL")
			return
		end

		vim.notify(
			"Opening browser for GitHub Copilot login. Code: " .. device_data.user_code,
			vim.log.levels.INFO
		)
		open_browser(verify_uri)

		local interval = tonumber(device_data.interval) or 5
		local expires_in = tonumber(device_data.expires_in) or 900
		local deadline = os.time() + expires_in

		poll_access_token(device_data.device_code, interval, deadline, function(access_data, access_err)
			if access_err then
				callback(nil, access_err)
				return
			end

			fetch_copilot_token(access_data.access_token, function(copilot_data, token_err)
				if token_err then
					callback(nil, token_err)
					return
				end

				local auth_data = {
					github_access_token = access_data.access_token,
					github_token_type = access_data.token_type,
					github_scope = access_data.scope,
					copilot_token = copilot_data.token,
					copilot_expires_at = copilot_data.expires_at,
					copilot_refresh_in = copilot_data.refresh_in,
					copilot_endpoints = copilot_data.endpoints,
					created_at = os.time(),
				}

				write_auth_data(auth_data)

				local endpoint = nil
				if copilot_data.endpoints and copilot_data.endpoints.api then
					endpoint = copilot_data.endpoints.api .. "/chat/completions"
				end

				callback({ token = copilot_data.token, endpoint = endpoint }, nil)
			end)
		end)
	end)
end

function M.logout()
	local token_path = get_token_path()
	if vim.fn.filereadable(token_path) == 1 then
		vim.fn.delete(token_path)
	end
end

return M
