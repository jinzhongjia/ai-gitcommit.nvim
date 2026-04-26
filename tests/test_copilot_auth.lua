local new_set = MiniTest.new_set
local helpers = require("tests.helpers")

local T = new_set()

local copilot
local tmp_dir
local original_xdg

--- Create a temporary directory for test fixtures
local function create_tmp_dir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

--- Write a JSON file to a path, creating parent dirs
local function write_json_file(path, data)
	local dir = vim.fn.fnamemodify(path, ":h")
	vim.fn.mkdir(dir, "p")
	vim.fn.writefile({ vim.json.encode(data) }, path)
end

--- Common pre_case: create temp dir, redirect XDG, clear caches
local function setup_isolated_env()
	tmp_dir = create_tmp_dir()
	original_xdg = vim.env.XDG_CONFIG_HOME
	vim.env.XDG_CONFIG_HOME = tmp_dir
	copilot.logout()
end

--- Common post_case: restore XDG, remove temp dir, clear caches
local function teardown_isolated_env()
	vim.env.XDG_CONFIG_HOME = original_xdg
	original_xdg = nil
	if tmp_dir and vim.fn.isdirectory(tmp_dir) == 1 then
		vim.fn.delete(tmp_dir, "rf")
	end
	tmp_dir = nil
	copilot.logout()
	copilot._testing.clear_mock_fetch_copilot_token()
	copilot._testing.clear_mock_fetch_models()
end

T["setup"] = function()
	helpers.reset_config()
	helpers.unload_module("ai-gitcommit.auth.copilot")
	copilot = require("ai-gitcommit.auth.copilot")
	copilot.logout()
end

-- ============================================================
-- is_copilot_token_valid
-- ============================================================
T["is_copilot_token_valid"] = new_set()

T["is_copilot_token_valid"]["returns false for nil"] = function()
	MiniTest.expect.equality(copilot._testing.is_copilot_token_valid(nil), false)
end

T["is_copilot_token_valid"]["returns false for empty token"] = function()
	MiniTest.expect.equality(copilot._testing.is_copilot_token_valid({ token = "" }), false)
end

T["is_copilot_token_valid"]["returns false for non-string token"] = function()
	MiniTest.expect.equality(copilot._testing.is_copilot_token_valid({ token = 123 }), false)
end

T["is_copilot_token_valid"]["returns true when no expires_at"] = function()
	MiniTest.expect.equality(copilot._testing.is_copilot_token_valid({ token = "abc" }), true)
end

T["is_copilot_token_valid"]["returns true when not expired"] = function()
	local future = os.time() + 3600
	MiniTest.expect.equality(copilot._testing.is_copilot_token_valid({ token = "abc", expires_at = future }), true)
end

T["is_copilot_token_valid"]["returns false when expired"] = function()
	local past = os.time() - 100
	MiniTest.expect.equality(copilot._testing.is_copilot_token_valid({ token = "abc", expires_at = past }), false)
end

T["is_copilot_token_valid"]["returns false when expiring within 30s"] = function()
	local soon = os.time() + 10
	MiniTest.expect.equality(copilot._testing.is_copilot_token_valid({ token = "abc", expires_at = soon }), false)
end

-- ============================================================
-- find_copilot_config_path
-- ============================================================
T["find_copilot_config_path"] = new_set()

T["find_copilot_config_path"]["returns a non-empty string"] = function()
	local path = copilot._testing.find_copilot_config_path()
	MiniTest.expect.equality(type(path), "string")
	MiniTest.expect.equality(path ~= "", true)
end

T["find_copilot_config_path"]["uses XDG_CONFIG_HOME when set"] = function()
	local xdg = os.getenv("XDG_CONFIG_HOME")
	local path = copilot._testing.find_copilot_config_path()
	if xdg and xdg ~= "" then
		MiniTest.expect.equality(path, xdg)
	end
end

-- ============================================================
-- read_copilot_plugin_oauth_token
-- ============================================================
T["read_copilot_plugin_oauth_token"] = new_set({
	hooks = {
		pre_case = setup_isolated_env,
		post_case = teardown_isolated_env,
	},
})

T["read_copilot_plugin_oauth_token"]["reads from hosts.json"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "hosts.json"), {
		["github.com"] = { oauth_token = "gho_test_hosts_token" },
	})

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, "gho_test_hosts_token")
end

T["read_copilot_plugin_oauth_token"]["reads from apps.json when hosts.json missing"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "apps.json"), {
		["github.com"] = { oauth_token = "gho_test_apps_token" },
	})

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, "gho_test_apps_token")
end

T["read_copilot_plugin_oauth_token"]["prefers hosts.json over apps.json"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "hosts.json"), {
		["github.com"] = { oauth_token = "gho_from_hosts" },
	})
	write_json_file(vim.fs.joinpath(copilot_dir, "apps.json"), {
		["github.com"] = { oauth_token = "gho_from_apps" },
	})

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, "gho_from_hosts")
end

T["read_copilot_plugin_oauth_token"]["handles key with github.com prefix"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "hosts.json"), {
		["github.com:copilot"] = { oauth_token = "gho_prefixed_token" },
	})

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, "gho_prefixed_token")
end

T["read_copilot_plugin_oauth_token"]["returns nil when no config files exist"] = function()
	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, nil)
end

T["read_copilot_plugin_oauth_token"]["returns nil for invalid JSON"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	vim.fn.mkdir(copilot_dir, "p")
	vim.fn.writefile({ "not valid json{{{" }, vim.fs.joinpath(copilot_dir, "hosts.json"))

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, nil)
end

T["read_copilot_plugin_oauth_token"]["returns nil when oauth_token is empty"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "hosts.json"), {
		["github.com"] = { oauth_token = "" },
	})

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, nil)
end

-- ============================================================
-- resolve_oauth_token
-- ============================================================
T["resolve_oauth_token"] = new_set({
	hooks = {
		pre_case = setup_isolated_env,
		post_case = teardown_isolated_env,
	},
})

T["resolve_oauth_token"]["returns nil when nothing is configured"] = function()
	local token = copilot._testing.resolve_oauth_token()
	MiniTest.expect.equality(token, nil)
end

T["resolve_oauth_token"]["returns memory cached token first"] = function()
	copilot._testing.set_cached_oauth_token("cached_token_123")
	local token = copilot._testing.resolve_oauth_token()
	MiniTest.expect.equality(token, "cached_token_123")
end

T["resolve_oauth_token"]["reads from copilot plugin config"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "hosts.json"), {
		["github.com"] = { oauth_token = "gho_plugin_token" },
	})

	local token = copilot._testing.resolve_oauth_token()
	MiniTest.expect.equality(token, "gho_plugin_token")

	-- Verify it was also cached
	MiniTest.expect.equality(copilot._testing.get_cached_oauth_token(), "gho_plugin_token")
end

T["resolve_oauth_token"]["memory cache beats plugin config"] = function()
	copilot._testing.set_cached_oauth_token("memory_token")
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "hosts.json"), {
		["github.com"] = { oauth_token = "plugin_token" },
	})

	local token = copilot._testing.resolve_oauth_token()
	MiniTest.expect.equality(token, "memory_token")
end

-- ============================================================
-- is_authenticated (public API)
-- ============================================================
T["is_authenticated"] = new_set({
	hooks = {
		pre_case = setup_isolated_env,
		post_case = teardown_isolated_env,
	},
})

T["is_authenticated"]["returns false when no token source available"] = function()
	MiniTest.expect.equality(copilot.is_authenticated(), false)
end

T["is_authenticated"]["returns true when copilot plugin token exists"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "hosts.json"), {
		["github.com"] = { oauth_token = "gho_test_token" },
	})

	MiniTest.expect.equality(copilot.is_authenticated(), true)
end

T["is_authenticated"]["returns true when memory cache is set"] = function()
	copilot._testing.set_cached_oauth_token("cached_token")
	MiniTest.expect.equality(copilot.is_authenticated(), true)
end

-- ============================================================
-- get_token (public API)
-- ============================================================
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
	MiniTest.expect.equality(type(result_err), "string")
	MiniTest.expect.equality(result_err:find("Not authenticated") ~= nil, true)
end

T["get_token"]["returns cached copilot token when valid"] = function()
	copilot._testing.set_cached_oauth_token("gho_oauth_token")
	copilot._testing.set_cached_copilot_token({
		token = "copilot_token_abc",
		expires_at = os.time() + 3600,
		endpoint = "https://example.com/chat/completions",
	})

	local result_data, result_err
	copilot.get_token(function(data, err)
		result_data = data
		result_err = err
	end)

	MiniTest.expect.equality(result_err, nil)
	MiniTest.expect.equality(result_data.token, "copilot_token_abc")
	MiniTest.expect.equality(result_data.endpoint, "https://example.com/chat/completions")
end

-- ============================================================
-- logout (public API)
-- ============================================================
T["logout"] = new_set({
	hooks = {
		pre_case = setup_isolated_env,
		post_case = teardown_isolated_env,
	},
})

T["logout"]["clears memory caches"] = function()
	copilot._testing.set_cached_oauth_token("test_token")
	copilot._testing.set_cached_copilot_token({ token = "cop_token", expires_at = os.time() + 3600 })

	copilot.logout()

	MiniTest.expect.equality(copilot._testing.get_cached_oauth_token(), nil)
	MiniTest.expect.equality(copilot._testing.get_cached_copilot_token(), nil)
end

T["logout"]["is idempotent"] = function()
	copilot.logout()
	copilot.logout() -- should not error
	MiniTest.expect.equality(copilot._testing.get_cached_oauth_token(), nil)
end

-- ============================================================
-- get_valid_copilot_token (concurrency)
-- ============================================================
T["get_valid_copilot_token"] = new_set({
	hooks = {
		pre_case = setup_isolated_env,
		post_case = teardown_isolated_env,
	},
})

T["get_valid_copilot_token"]["returns cached token immediately"] = function()
	copilot._testing.set_cached_copilot_token({
		token = "valid_token",
		expires_at = os.time() + 3600,
		endpoint = "https://api.example.com/chat/completions",
	})

	local result_data, result_err
	copilot._testing.get_valid_copilot_token("oauth_token", function(data, err)
		result_data = data
		result_err = err
	end)

	-- Should return synchronously since cached
	MiniTest.expect.equality(result_err, nil)
	MiniTest.expect.equality(result_data.token, "valid_token")
	MiniTest.expect.equality(result_data.endpoint, "https://api.example.com/chat/completions")
end

T["get_valid_copilot_token"]["concurrent requests all receive error on refresh failure"] = function()
	local call_count = 0
	local results = {}

	copilot._testing.set_mock_fetch_copilot_token(function(_, cb)
		call_count = call_count + 1
		vim.schedule(function()
			cb(nil, "Simulated auth failure")
		end)
	end)

	for i = 1, 3 do
		copilot._testing.get_valid_copilot_token("oauth_token", function(data, err)
			results[i] = { data = data, err = err }
		end)
	end

	vim.wait(100, function()
		return #results == 3 and results[1].err ~= nil
	end)

	MiniTest.expect.equality(call_count, 1)
	for i = 1, 3 do
		MiniTest.expect.equality(results[i].data, nil)
		MiniTest.expect.equality(results[i].err, "Simulated auth failure")
	end
end

-- ============================================================
-- parse_models_response
-- ============================================================
T["parse_models_response"] = new_set()

T["parse_models_response"]["keeps only picker-enabled chat models"] = function()
	local body = vim.json.encode({
		data = {
			{ id = "gpt-4o", model_picker_enabled = true, capabilities = { type = "chat" } },
			{ id = "missing-caps", model_picker_enabled = true },
			{ id = "text-embed", model_picker_enabled = true, capabilities = { type = "embeddings" } },
			{ id = "hidden", model_picker_enabled = false, capabilities = { type = "chat" } },
			{
				id = "claude-sonnet-4",
				model_picker_enabled = true,
				capabilities = { type = { "chat", "completions" } },
			},
		},
	})

	local ids, err = copilot._testing.parse_models_response(body)
	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(#ids, 2)
	-- No billing info on either → stable API order
	MiniTest.expect.equality(ids[1], "gpt-4o")
	MiniTest.expect.equality(ids[2], "claude-sonnet-4")
end

T["parse_models_response"]["sorts by billing multiplier ascending"] = function()
	local body = vim.json.encode({
		data = {
			{
				id = "claude-opus",
				model_picker_enabled = true,
				capabilities = { type = "chat" },
				billing = { multiplier = 10 },
			},
			{
				id = "grok-code-fast-1",
				model_picker_enabled = true,
				capabilities = { type = "chat" },
				billing = { multiplier = 0 },
			},
			{
				id = "gpt-4o",
				model_picker_enabled = true,
				capabilities = { type = "chat" },
				billing = { multiplier = 1 },
			},
			{
				id = "mystery-model",
				model_picker_enabled = true,
				capabilities = { type = "chat" },
				-- no billing info → ranked last
			},
		},
	})

	local ids, err = copilot._testing.parse_models_response(body)
	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(ids[1], "grok-code-fast-1")
	MiniTest.expect.equality(ids[2], "gpt-4o")
	MiniTest.expect.equality(ids[3], "claude-opus")
	MiniTest.expect.equality(ids[4], "mystery-model")
end

T["parse_models_response"]["preserves api order when multipliers are equal"] = function()
	local body = vim.json.encode({
		data = {
			{
				id = "a-model",
				model_picker_enabled = true,
				capabilities = { type = "chat" },
				billing = { multiplier = 0 },
			},
			{
				id = "b-model",
				model_picker_enabled = true,
				capabilities = { type = "chat" },
				billing = { multiplier = 0 },
			},
		},
	})

	local ids, err = copilot._testing.parse_models_response(body)
	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(ids[1], "a-model")
	MiniTest.expect.equality(ids[2], "b-model")
end

T["parse_models_response"]["errors on empty result"] = function()
	local body = vim.json.encode({ data = {} })
	local ids, err = copilot._testing.parse_models_response(body)
	MiniTest.expect.equality(ids, nil)
	MiniTest.expect.equality(type(err), "string")
end

T["parse_models_response"]["errors on malformed json"] = function()
	local ids, err = copilot._testing.parse_models_response("not json")
	MiniTest.expect.equality(ids, nil)
	MiniTest.expect.equality(type(err), "string")
end

-- ============================================================
-- models_url_from_chat_endpoint
-- ============================================================
T["models_url_from_chat_endpoint"] = new_set()

T["models_url_from_chat_endpoint"]["derives /models from chat endpoint"] = function()
	local url = copilot._testing.models_url_from_chat_endpoint("https://api.githubcopilot.com/chat/completions")
	MiniTest.expect.equality(url, "https://api.githubcopilot.com/models")
end

T["models_url_from_chat_endpoint"]["works with a different host"] = function()
	local url = copilot._testing.models_url_from_chat_endpoint("https://proxy.example.com/v1/chat/completions")
	MiniTest.expect.equality(url, "https://proxy.example.com/models")
end

-- ============================================================
-- fetch_models (public API)
-- ============================================================
T["fetch_models"] = new_set({
	hooks = {
		pre_case = setup_isolated_env,
		post_case = teardown_isolated_env,
	},
})

T["fetch_models"]["returns cached ids without refetch"] = function()
	copilot._testing.set_cached_models({
		ids = { "cached-model" },
		expires_at = os.time() + 300,
	})

	local result_ids, result_err
	copilot.fetch_models(function(ids, err)
		result_ids = ids
		result_err = err
	end)

	MiniTest.expect.equality(result_err, nil)
	MiniTest.expect.equality(result_ids[1], "cached-model")
end

T["fetch_models"]["uses mocked fetch and caches result"] = function()
	copilot._testing.set_cached_oauth_token("gho_test")
	copilot._testing.set_cached_copilot_token({
		token = "copilot_token",
		expires_at = os.time() + 3600,
		endpoint = "https://api.githubcopilot.com/chat/completions",
	})

	copilot._testing.set_mock_fetch_models(function(_token, _endpoint, cb)
		vim.schedule(function()
			cb({ "gpt-4o", "claude-sonnet-4" }, nil)
		end)
	end)

	local result_ids, result_err
	copilot.fetch_models(function(ids, err)
		result_ids = ids
		result_err = err
	end)

	vim.wait(200, function()
		return result_ids ~= nil or result_err ~= nil
	end)

	MiniTest.expect.equality(result_err, nil)
	MiniTest.expect.equality(result_ids[1], "gpt-4o")

	local cached = copilot._testing.get_cached_models()
	MiniTest.expect.equality(cached.ids[1], "gpt-4o")
end

T["fetch_models"]["propagates fetch errors without caching"] = function()
	copilot._testing.set_cached_oauth_token("gho_test")
	copilot._testing.set_cached_copilot_token({
		token = "copilot_token",
		expires_at = os.time() + 3600,
		endpoint = "https://api.githubcopilot.com/chat/completions",
	})

	copilot._testing.set_mock_fetch_models(function(_token, _endpoint, cb)
		vim.schedule(function()
			cb(nil, "simulated failure")
		end)
	end)

	local result_ids, result_err
	copilot.fetch_models(function(ids, err)
		result_ids = ids
		result_err = err
	end)

	vim.wait(200, function()
		return result_ids ~= nil or result_err ~= nil
	end)

	MiniTest.expect.equality(result_ids, nil)
	MiniTest.expect.equality(result_err, "simulated failure")
	MiniTest.expect.equality(copilot._testing.get_cached_models(), nil)
end

return T
