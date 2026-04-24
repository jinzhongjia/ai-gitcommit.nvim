local new_set = MiniTest.new_set
local helpers = require("tests.helpers")

local T = new_set()

---@param overrides table?
---@return table
local function run_generate_with_mocks(overrides)
	overrides = overrides or {}

	local original_notify = vim.notify
	local original_loaded = {}
	local modules = {
		"ai-gitcommit",
		"ai-gitcommit.autogen",
		"ai-gitcommit.buffer",
		"ai-gitcommit.buffer_state",
		"ai-gitcommit.commands",
		"ai-gitcommit.config",
		"ai-gitcommit.context",
		"ai-gitcommit.generator",
		"ai-gitcommit.git",
		"ai-gitcommit.prompt",
		"ai-gitcommit.providers",
		"ai-gitcommit.auth",
		"ai-gitcommit.typewriter",
	}

	for _, name in ipairs(modules) do
		original_loaded[name] = package.loaded[name]
		package.loaded[name] = nil
	end

	local notifications = {}
	vim.notify = function(msg, level)
		table.insert(notifications, { msg = msg, level = level })
	end

	package.loaded["ai-gitcommit.buffer"] = {
		is_gitcommit_buffer = function()
			return true
		end,
		find_first_comment_line = function(_)
			return 1
		end,
	}

	package.loaded["ai-gitcommit.config"] = {
		validate_provider = function()
			return true, nil
		end,
		get_provider = function()
			return {
				name = "openai",
				config = {
					api_key = "test-key",
					model = "gpt-4o-mini",
					endpoint = "https://api.openai.com/v1/chat/completions",
					max_tokens = 500,
				},
			}, nil
		end,
		get = function()
			return {
				languages = { "English" },
				prompt_template = nil,
				context = { max_diff_lines = 500, max_diff_chars = 15000 },
				filter = { exclude_patterns = {}, exclude_paths = {}, include_only = nil },
				providers = {
					openai = {
						api_key = "test-key",
						model = "gpt-4o-mini",
						endpoint = "https://api.openai.com/v1/chat/completions",
						max_tokens = 500,
					},
				},
			}
		end,
	}

	package.loaded["ai-gitcommit.git"] = {
		get_staged_diff = function(callback)
			local diff = overrides.diff or "diff --git a/a.lua b/a.lua"
			callback(diff, overrides.diff_err)
		end,
		get_staged_files = function(callback)
			callback(overrides.files or { { status = "M", file = "a.lua" } }, overrides.files_err)
		end,
	}

	package.loaded["ai-gitcommit.prompt"] = {
		build = function(_)
			return "prompt"
		end,
	}

	package.loaded["ai-gitcommit.context"] = {
		build_context = function(diff, _)
			return diff
		end,
	}

	package.loaded["ai-gitcommit.auth"] = {
		is_authenticated = function(_)
			return false
		end,
		get_token = function(_, callback)
			callback(nil, "Not authenticated")
		end,
	}

	package.loaded["ai-gitcommit.typewriter"] = {
		new = function(_)
			return {
				push = function(_, _)
				end,
				finish = function(_, callback)
					callback()
				end,
				stop = function(_)
				end,
			}
		end,
	}

	package.loaded["ai-gitcommit.providers"] = {
		get = function(_)
			return {
				generate = function(_, _, on_chunk, on_done, _)
					if overrides.chunk then
						on_chunk(overrides.chunk)
					end
					on_done()
				end,
				has_credentials = function(_)
					return true
				end,
				credential_status = function(_)
					return "configured"
				end,
				resolve_credentials = function(_, callback)
					callback({ api_key = "test-key" }, nil)
				end,
			}
		end,
		has_current_credentials = function()
			return true
		end,
		status = function(_)
			return "configured"
		end,
	}

	local bufnr = helpers.create_gitcommit_buffer()
	local ai = require("ai-gitcommit")
	ai.generate()

	helpers.cleanup_buffer(bufnr)

	vim.notify = original_notify
	for _, name in ipairs(modules) do
		package.loaded[name] = original_loaded[name]
	end

	return notifications
end

T["generate"] = new_set()

T["generate"]["shows error when staged diff command fails"] = function()
	local notifications = run_generate_with_mocks({ diff_err = "fatal: git error" })

	MiniTest.expect.equality(#notifications > 0, true)
	MiniTest.expect.equality(notifications[1].msg, "Generating commit message...")
	MiniTest.expect.equality(notifications[2].msg, "Error: fatal: git error")
end

T["generate"]["shows warning when provider returns empty content"] = function()
	local notifications = run_generate_with_mocks({})

	MiniTest.expect.equality(#notifications > 0, true)
	MiniTest.expect.equality(notifications[1].msg, "Generating commit message...")
	MiniTest.expect.equality(notifications[2].msg, "No message content received from provider")
end

T["generate"]["shows success when provider returns content"] = function()
	local notifications = run_generate_with_mocks({ chunk = "feat: add tests" })

	MiniTest.expect.equality(#notifications > 0, true)
	MiniTest.expect.equality(notifications[1].msg, "Generating commit message...")
	MiniTest.expect.equality(notifications[2].msg, "Commit message generated!")
end

return T
