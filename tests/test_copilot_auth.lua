local new_set = MiniTest.new_set
local helpers = require("tests.helpers")

local T = new_set()

local copilot
local tmp_dir
local original_xdg

---@return string
local function create_tmp_dir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

---@param path string
---@param data table
local function write_json_file(path, data)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile({ vim.json.encode(data) }, path)
end

local function setup_isolated_env()
	tmp_dir = create_tmp_dir()
	original_xdg = vim.env.XDG_CONFIG_HOME
	vim.env.XDG_CONFIG_HOME = tmp_dir
	copilot.logout()
end

local function teardown_isolated_env()
	vim.env.XDG_CONFIG_HOME = original_xdg
	original_xdg = nil
	if tmp_dir and vim.fn.isdirectory(tmp_dir) == 1 then
		vim.fn.delete(tmp_dir, "rf")
	end
	tmp_dir = nil
	copilot.logout()
end

---@param handler fun(args: string[]): table
---@param fn fun()
local function with_system(handler, fn)
	local original_system = vim.system
	vim.system = function(args, _, cb)
		local obj = handler(args)
		if cb then
			cb({ code = obj.code or 0, stdout = obj.stdout or "", stderr = obj.stderr or "" })
		end
		return {
			wait = function()
				return obj
			end,
			is_closing = function()
				return false
			end,
			kill = function(_, _) end,
		}
	end

	local ok, err = pcall(fn)
	vim.system = original_system
	if not ok then
		error(err)
	end
end

---@param models table[]
---@return string
local function models_body(models)
	return vim.json.encode({ data = models })
end

T["setup"] = function()
	helpers.reset_config()
	helpers.unload_module("ai-gitcommit.auth.copilot")
	copilot = require("ai-gitcommit.auth.copilot")
	copilot.logout()
end

T["is_authenticated"] = new_set({
	hooks = {
		pre_case = setup_isolated_env,
		post_case = teardown_isolated_env,
	},
})

T["is_authenticated"]["returns false when no token source exists"] = function()
	MiniTest.expect.equality(copilot.is_authenticated(), false)
end

T["is_authenticated"]["reads hosts.json token"] = function()
	write_json_file(vim.fs.joinpath(tmp_dir, "github-copilot", "hosts.json"), {
		["github.com"] = { oauth_token = "gho_hosts" },
	})

	MiniTest.expect.equality(copilot.is_authenticated(), true)
end

T["is_authenticated"]["falls back to apps.json"] = function()
	write_json_file(vim.fs.joinpath(tmp_dir, "github-copilot", "apps.json"), {
		["github.com"] = { oauth_token = "gho_apps" },
	})

	MiniTest.expect.equality(copilot.is_authenticated(), true)
end

T["get_token"] = new_set({
	hooks = {
		pre_case = setup_isolated_env,
		post_case = teardown_isolated_env,
	},
})

T["get_token"]["returns error when not authenticated"] = function()
	local result_data, result_err
	copilot.get_token(function(data, err)
		result_data = data
		result_err = err
	end)

	MiniTest.expect.equality(result_data, nil)
	MiniTest.expect.equality(result_err:find("Not authenticated", 1, true) ~= nil, true)
end

T["get_token"]["fetches and caches Copilot token"] = function()
	write_json_file(vim.fs.joinpath(tmp_dir, "github-copilot", "hosts.json"), {
		["github.com"] = { oauth_token = "gho_oauth" },
	})

	local calls = 0
	with_system(function(args)
		calls = calls + 1
		MiniTest.expect.equality(args[#args], "https://api.github.com/copilot_internal/v2/token")
		return {
			stdout = vim.json.encode({
				token = "copilot_token",
				expires_at = os.time() + 3600,
				endpoints = { api = "https://api.githubcopilot.com" },
			}),
		}
	end, function()
		local first, second
		copilot.get_token(function(data)
			first = data
		end)
		vim.wait(200, function()
			return first ~= nil
		end)
		copilot.get_token(function(data)
			second = data
		end)

		MiniTest.expect.equality(first.token, "copilot_token")
		MiniTest.expect.equality(first.endpoint, "https://api.githubcopilot.com/chat/completions")
		MiniTest.expect.equality(second.token, "copilot_token")
		MiniTest.expect.equality(calls, 1)
	end)
end

T["get_token"]["coalesces concurrent token refreshes"] = function()
	write_json_file(vim.fs.joinpath(tmp_dir, "github-copilot", "hosts.json"), {
		["github.com"] = { oauth_token = "gho_oauth" },
	})

	local calls = 0
	with_system(function(_)
		calls = calls + 1
		return { stdout = vim.json.encode({ token = "copilot_token", expires_at = os.time() + 3600 }) }
	end, function()
		local results = {}
		for i = 1, 3 do
			copilot.get_token(function(data, err)
				results[i] = { data = data, err = err }
			end)
		end

		vim.wait(200, function()
			return results[1] ~= nil and results[2] ~= nil and results[3] ~= nil
		end)

		MiniTest.expect.equality(calls, 1)
		for i = 1, 3 do
			MiniTest.expect.equality(results[i].err, nil)
			MiniTest.expect.equality(results[i].data.token, "copilot_token")
		end
	end)
end

T["fetch_models"] = new_set({
	hooks = {
		pre_case = setup_isolated_env,
		post_case = teardown_isolated_env,
	},
})

T["fetch_models"]["sorts by billing multiplier and keeps endpoint kind"] = function()
	write_json_file(vim.fs.joinpath(tmp_dir, "github-copilot", "hosts.json"), {
		["github.com"] = { oauth_token = "gho_oauth" },
	})

	local token_calls = 0
	local model_calls = 0
	with_system(function(args)
		local url = args[#args]
		if url:find("/copilot_internal/v2/token", 1, true) then
			token_calls = token_calls + 1
			return {
				stdout = vim.json.encode({
					token = "copilot_token",
					expires_at = os.time() + 3600,
					endpoints = { api = "https://api.githubcopilot.com" },
				}),
			}
		end

		model_calls = model_calls + 1
		MiniTest.expect.equality(url, "https://api.githubcopilot.com/models")
		return {
			stdout = models_body({
				{
					id = "expensive",
					model_picker_enabled = true,
					capabilities = { type = "chat" },
					billing = { multiplier = 10 },
				},
				{
					id = "gpt-5.3-codex",
					model_picker_enabled = true,
					capabilities = { type = "chat" },
					billing = { multiplier = 0 },
					supported_endpoints = { "/responses" },
				},
				{
					id = "gpt-4o",
					model_picker_enabled = true,
					capabilities = { type = "chat" },
					billing = { multiplier = 1 },
					supported_endpoints = { "/chat/completions" },
				},
				{ id = "hidden", model_picker_enabled = false, capabilities = { type = "chat" } },
			}),
		}
	end, function()
		local first, second
		copilot.fetch_models(function(entries)
			first = entries
		end)
		vim.wait(200, function()
			return first ~= nil
		end)
		copilot.fetch_models(function(entries)
			second = entries
		end)

		MiniTest.expect.equality(first[1].id, "gpt-5.3-codex")
		MiniTest.expect.equality(first[1].endpoint, "responses")
		MiniTest.expect.equality(first[2].id, "gpt-4o")
		MiniTest.expect.equality(second[1].id, "gpt-5.3-codex")
		MiniTest.expect.equality(token_calls, 1)
		MiniTest.expect.equality(model_calls, 1)
	end)
end

T["fetch_models"]["returns parser errors"] = function()
	write_json_file(vim.fs.joinpath(tmp_dir, "github-copilot", "hosts.json"), {
		["github.com"] = { oauth_token = "gho_oauth" },
	})

	with_system(function(args)
		local url = args[#args]
		if url:find("/copilot_internal/v2/token", 1, true) then
			return { stdout = vim.json.encode({ token = "copilot_token", expires_at = os.time() + 3600 }) }
		end
		return { stdout = vim.json.encode({ data = {} }) }
	end, function()
		local result_entries, result_err
		copilot.fetch_models(function(entries, err)
			result_entries = entries
			result_err = err
		end)
		vim.wait(200, function()
			return result_err ~= nil
		end)

		MiniTest.expect.equality(result_entries, nil)
		MiniTest.expect.equality(result_err, "No usable chat models returned by Copilot")
	end)
end

return T
