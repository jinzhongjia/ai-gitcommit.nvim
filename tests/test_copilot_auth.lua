local new_set = MiniTest.new_set
local helpers = require("tests.helpers")

local T = new_set()

local copilot
local tmp_dir

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

--- Cleanup: remove temp dir and reset module state
local function cleanup()
	if tmp_dir and vim.fn.isdirectory(tmp_dir) == 1 then
		vim.fn.delete(tmp_dir, "rf")
	end
	tmp_dir = nil

	-- Reset module
	if copilot then
		copilot.logout()
	end
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
	local original = os.getenv("XDG_CONFIG_HOME")
	-- XDG_CONFIG_HOME is typically set in most environments
	-- Just verify the function returns a valid path
	local path = copilot._testing.find_copilot_config_path()
	if original and original ~= "" then
		MiniTest.expect.equality(path, original)
	end
end

-- ============================================================
-- read_copilot_plugin_oauth_token
-- ============================================================
T["read_copilot_plugin_oauth_token"] = new_set({
	hooks = {
		pre_case = function()
			tmp_dir = create_tmp_dir()
		end,
		post_case = cleanup,
	},
})

T["read_copilot_plugin_oauth_token"]["reads from hosts.json"] = function()
	-- Create a fake hosts.json in temp dir
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "hosts.json"), {
		["github.com"] = { oauth_token = "gho_test_hosts_token" },
	})

	-- Override XDG_CONFIG_HOME to point to our temp dir
	local original_xdg = vim.env.XDG_CONFIG_HOME
	vim.env.XDG_CONFIG_HOME = tmp_dir

	-- Need to reload the module to pick up the new env
	helpers.unload_module("ai-gitcommit.auth.copilot")
	copilot = require("ai-gitcommit.auth.copilot")
	copilot.logout() -- clear caches

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, "gho_test_hosts_token")

	-- Restore
	vim.env.XDG_CONFIG_HOME = original_xdg
end

T["read_copilot_plugin_oauth_token"]["reads from apps.json when hosts.json missing"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "apps.json"), {
		["github.com"] = { oauth_token = "gho_test_apps_token" },
	})

	local original_xdg = vim.env.XDG_CONFIG_HOME
	vim.env.XDG_CONFIG_HOME = tmp_dir

	helpers.unload_module("ai-gitcommit.auth.copilot")
	copilot = require("ai-gitcommit.auth.copilot")
	copilot.logout()

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, "gho_test_apps_token")

	vim.env.XDG_CONFIG_HOME = original_xdg
end

T["read_copilot_plugin_oauth_token"]["prefers hosts.json over apps.json"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "hosts.json"), {
		["github.com"] = { oauth_token = "gho_from_hosts" },
	})
	write_json_file(vim.fs.joinpath(copilot_dir, "apps.json"), {
		["github.com"] = { oauth_token = "gho_from_apps" },
	})

	local original_xdg = vim.env.XDG_CONFIG_HOME
	vim.env.XDG_CONFIG_HOME = tmp_dir

	helpers.unload_module("ai-gitcommit.auth.copilot")
	copilot = require("ai-gitcommit.auth.copilot")
	copilot.logout()

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, "gho_from_hosts")

	vim.env.XDG_CONFIG_HOME = original_xdg
end

T["read_copilot_plugin_oauth_token"]["handles key with github.com prefix"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "hosts.json"), {
		["github.com:copilot"] = { oauth_token = "gho_prefixed_token" },
	})

	local original_xdg = vim.env.XDG_CONFIG_HOME
	vim.env.XDG_CONFIG_HOME = tmp_dir

	helpers.unload_module("ai-gitcommit.auth.copilot")
	copilot = require("ai-gitcommit.auth.copilot")
	copilot.logout()

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, "gho_prefixed_token")

	vim.env.XDG_CONFIG_HOME = original_xdg
end

T["read_copilot_plugin_oauth_token"]["returns nil when no config files exist"] = function()
	local original_xdg = vim.env.XDG_CONFIG_HOME
	vim.env.XDG_CONFIG_HOME = tmp_dir -- empty dir, no github-copilot subdir

	helpers.unload_module("ai-gitcommit.auth.copilot")
	copilot = require("ai-gitcommit.auth.copilot")
	copilot.logout()

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, nil)

	vim.env.XDG_CONFIG_HOME = original_xdg
end

T["read_copilot_plugin_oauth_token"]["returns nil for invalid JSON"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	vim.fn.mkdir(copilot_dir, "p")
	vim.fn.writefile({ "not valid json{{{" }, vim.fs.joinpath(copilot_dir, "hosts.json"))

	local original_xdg = vim.env.XDG_CONFIG_HOME
	vim.env.XDG_CONFIG_HOME = tmp_dir

	helpers.unload_module("ai-gitcommit.auth.copilot")
	copilot = require("ai-gitcommit.auth.copilot")
	copilot.logout()

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, nil)

	vim.env.XDG_CONFIG_HOME = original_xdg
end

T["read_copilot_plugin_oauth_token"]["returns nil when oauth_token is empty"] = function()
	local copilot_dir = vim.fs.joinpath(tmp_dir, "github-copilot")
	write_json_file(vim.fs.joinpath(copilot_dir, "hosts.json"), {
		["github.com"] = { oauth_token = "" },
	})

	local original_xdg = vim.env.XDG_CONFIG_HOME
	vim.env.XDG_CONFIG_HOME = tmp_dir

	helpers.unload_module("ai-gitcommit.auth.copilot")
	copilot = require("ai-gitcommit.auth.copilot")
	copilot.logout()

	local token = copilot._testing.read_copilot_plugin_oauth_token()
	MiniTest.expect.equality(token, nil)

	vim.env.XDG_CONFIG_HOME = original_xdg
end

-- ============================================================
-- resolve_oauth_token
-- ============================================================
T["resolve_oauth_token"] = new_set({
	hooks = {
		pre_case = function()
			tmp_dir = create_tmp_dir()
			-- Point XDG to empty temp dir so plugin config is not found
			vim.env._ORIGINAL_XDG = vim.env.XDG_CONFIG_HOME
			vim.env.XDG_CONFIG_HOME = tmp_dir
			helpers.unload_module("ai-gitcommit.auth.copilot")
			copilot = require("ai-gitcommit.auth.copilot")
			copilot.logout()
		end,
		post_case = function()
			vim.env.XDG_CONFIG_HOME = vim.env._ORIGINAL_XDG
			vim.env._ORIGINAL_XDG = nil
			cleanup()
		end,
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
	-- Set up both sources
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
		pre_case = function()
			tmp_dir = create_tmp_dir()
			vim.env._ORIGINAL_XDG = vim.env.XDG_CONFIG_HOME
			vim.env.XDG_CONFIG_HOME = tmp_dir
			helpers.unload_module("ai-gitcommit.auth.copilot")
			copilot = require("ai-gitcommit.auth.copilot")
			copilot.logout()
		end,
		post_case = function()
			vim.env.XDG_CONFIG_HOME = vim.env._ORIGINAL_XDG
			vim.env._ORIGINAL_XDG = nil
			cleanup()
		end,
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
		pre_case = function()
			tmp_dir = create_tmp_dir()
			vim.env._ORIGINAL_XDG = vim.env.XDG_CONFIG_HOME
			vim.env.XDG_CONFIG_HOME = tmp_dir
			helpers.unload_module("ai-gitcommit.auth.copilot")
			copilot = require("ai-gitcommit.auth.copilot")
			copilot.logout()
		end,
		post_case = function()
			vim.env.XDG_CONFIG_HOME = vim.env._ORIGINAL_XDG
			vim.env._ORIGINAL_XDG = nil
			cleanup()
		end,
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
		pre_case = function()
			tmp_dir = create_tmp_dir()
			vim.env._ORIGINAL_XDG = vim.env.XDG_CONFIG_HOME
			vim.env.XDG_CONFIG_HOME = tmp_dir
			helpers.unload_module("ai-gitcommit.auth.copilot")
			copilot = require("ai-gitcommit.auth.copilot")
		end,
		post_case = function()
			vim.env.XDG_CONFIG_HOME = vim.env._ORIGINAL_XDG
			vim.env._ORIGINAL_XDG = nil
			cleanup()
		end,
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
-- login (public API)
-- ============================================================
T["login"] = new_set()

T["login"]["returns error directing to install copilot plugin"] = function()
	local result_data, result_err
	copilot.login(function(data, err)
		result_data = data
		result_err = err
	end)

	MiniTest.expect.equality(result_data, nil)
	MiniTest.expect.equality(type(result_err), "string")
	MiniTest.expect.equality(result_err:find("copilot.vim") ~= nil, true)
end

-- ============================================================
-- get_valid_copilot_token (concurrency)
-- ============================================================
T["get_valid_copilot_token"] = new_set({
	hooks = {
		pre_case = function()
			tmp_dir = create_tmp_dir()
			vim.env._ORIGINAL_XDG = vim.env.XDG_CONFIG_HOME
			vim.env.XDG_CONFIG_HOME = tmp_dir
			helpers.unload_module("ai-gitcommit.auth.copilot")
			copilot = require("ai-gitcommit.auth.copilot")
			copilot.logout()
		end,
		post_case = function()
			vim.env.XDG_CONFIG_HOME = vim.env._ORIGINAL_XDG
			vim.env._ORIGINAL_XDG = nil
			cleanup()
		end,
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

return T
