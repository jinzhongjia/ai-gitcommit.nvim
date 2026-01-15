local M = {}

local AUTHORIZATION_URL = "https://console.anthropic.com/oauth/authorize"
local TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
local CREATE_API_KEY_URL = "https://api.anthropic.com/api/oauth/claude_cli/create_api_key"
local REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback"
local CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
local SCOPES = "org:create_api_key user:profile user:inference"

local IS_WINDOWS = vim.fn.has("win32") == 1

local function get_token_path()
	return vim.fs.joinpath(vim.fn.stdpath("data"), "ai-gitcommit", "anthropic.json")
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

---@param length number
---@return string
local function generate_random_string(length)
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
	local result = {}
	for _ = 1, length do
		local idx = math.random(1, #chars)
		table.insert(result, chars:sub(idx, idx))
	end
	return table.concat(result)
end

---@param hex string
---@return string
local function hex_to_bytes(hex)
	local bytes = {}
	for i = 1, #hex, 2 do
		local byte = tonumber(hex:sub(i, i + 1), 16)
		table.insert(bytes, string.char(byte))
	end
	return table.concat(bytes)
end

---@param data string
---@return string
local function base64url_encode(data)
	local b64 = vim.base64.encode(data)
	return b64:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

---@return string verifier
---@return string challenge
local function generate_pkce()
	local verifier = generate_random_string(43)
	local hash_hex = vim.fn.sha256(verifier)
	local hash_bytes = hex_to_bytes(hash_hex)
	local challenge = base64url_encode(hash_bytes)
	return verifier, challenge
end

---@param challenge string
---@param verifier string
---@return string
local function build_auth_url(challenge, verifier)
	local params = {
		"code=true",
		"client_id=" .. CLIENT_ID,
		"response_type=code",
		"redirect_uri=" .. vim.uri_encode(REDIRECT_URI),
		"scope=" .. vim.uri_encode(SCOPES),
		"code_challenge=" .. challenge,
		"code_challenge_method=S256",
		"state=" .. verifier,
	}
	return AUTHORIZATION_URL .. "?" .. table.concat(params, "&")
end

---@return boolean
function M.is_authenticated()
	local token_path = get_token_path()
	local content = read_file(token_path)
	if not content then
		return false
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok or not data then
		return false
	end

	return data.api_key ~= nil
end

---@param api_key string
local function store_api_key(api_key)
	local data_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "ai-gitcommit")
	vim.fn.mkdir(data_dir, "p")

	local token_path = get_token_path()
	local file_data = {
		api_key = api_key,
		created_at = os.time(),
	}

	write_file(token_path, vim.json.encode(file_data))
end

---@param callback fun(data: table?, err: string?)
function M.get_token(callback)
	if not M.is_authenticated() then
		callback(nil, "Not authenticated. Run :AICommit login")
		return
	end

	local token_path = get_token_path()
	local content = read_file(token_path)
	if not content then
		callback(nil, "Token file not found")
		return
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok or not data or not data.api_key then
		callback(nil, "Invalid token file")
		return
	end

	callback({ token = data.api_key })
end

---@param code string
---@param verifier string
---@param callback fun(data: table?, err: string?)
local function exchange_code(code, verifier, callback)
	local splits = vim.split(code, "#", { plain = true })
	local auth_code = splits[1]
	local state = splits[2]

	local body = vim.json.encode({
		code = auth_code,
		state = state,
		grant_type = "authorization_code",
		client_id = CLIENT_ID,
		redirect_uri = REDIRECT_URI,
		code_verifier = verifier,
	})

	curl({
		"-s",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-d",
		body,
		TOKEN_URL,
	}, function(stdout, exit_code)
		if exit_code ~= 0 then
			callback(nil, "Failed to exchange code")
			return
		end

		local ok, data = pcall(vim.json.decode, stdout)
		if not ok then
			callback(nil, "Invalid token response")
			return
		end

		if data.error then
			callback(nil, "OAuth error: " .. (data.error_description or data.error))
			return
		end

		if not data.access_token then
			callback(nil, "No access token in response")
			return
		end

		callback({
			access_token = data.access_token,
			refresh_token = data.refresh_token,
			expires_in = data.expires_in,
		})
	end)
end

---@param access_token string
---@param callback fun(api_key: string?, err: string?)
local function create_api_key(access_token, callback)
	curl({
		"-s",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-H",
		"Authorization: Bearer " .. access_token,
		CREATE_API_KEY_URL,
	}, function(stdout, exit_code)
		if exit_code ~= 0 then
			callback(nil, "Failed to create API key")
			return
		end

		local ok, data = pcall(vim.json.decode, stdout)
		if not ok then
			callback(nil, "Invalid API key response")
			return
		end

		if data.error then
			callback(nil, "API key error: " .. (data.error.message or data.error))
			return
		end

		if not data.raw_key then
			callback(nil, "No API key in response")
			return
		end

		callback(data.raw_key)
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

---@param callback fun(data: table?, err: string?)
function M.login(callback)
	math.randomseed(os.time())

	local verifier, challenge = generate_pkce()
	local auth_url = build_auth_url(challenge, verifier)

	vim.notify(
		"Opening browser for Anthropic Console login...\n\nAfter authorizing, copy the code from the page and paste it here.",
		vim.log.levels.INFO
	)

	open_browser(auth_url)

	vim.schedule(function()
		vim.ui.input({ prompt = "Paste authorization code: " }, function(code)
			if not code or code == "" then
				callback(nil, "No code provided")
				return
			end

			exchange_code(code, verifier, function(tokens, err)
				if err then
					callback(nil, err)
					return
				end

				create_api_key(tokens.access_token, function(api_key, key_err)
					if key_err then
						callback(nil, key_err)
						return
					end

					store_api_key(api_key)
					vim.notify("Anthropic API key created and stored!", vim.log.levels.INFO)
					callback({ api_key = api_key })
				end)
			end)
		end)
	end)
end

function M.logout()
	local token_path = get_token_path()
	if vim.fn.filereadable(token_path) == 1 then
		vim.fn.delete(token_path)
	end
	vim.notify("Anthropic logged out", vim.log.levels.INFO)
end

return M
