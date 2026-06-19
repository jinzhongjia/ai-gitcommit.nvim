local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

---@param overrides? table
---@param callback fun(generator: table, ctx: table)
---@return nil
local function with_generator_mocks(overrides, callback)
	overrides = overrides or {}

	local original_notify = vim.notify
	local original_select = vim.ui.select
	local original_loaded = {}
	local modules = {
		"ai-gitcommit.buffer",
		"ai-gitcommit.buffer_state",
		"ai-gitcommit.config",
		"ai-gitcommit.context",
		"ai-gitcommit.generator",
		"ai-gitcommit.git",
		"ai-gitcommit.prompt",
		"ai-gitcommit.providers",
		"ai-gitcommit.typewriter",
	}

	for _, name in ipairs(modules) do
		original_loaded[name] = package.loaded[name]
		package.loaded[name] = nil
	end

	local notifications = {}
	local states = {}
	local captured = {}

	vim.notify = function(msg, level)
		table.insert(notifications, { msg = msg, level = level })
	end

	vim.ui.select = overrides.ui_select or function(items, opts, on_choice)
		captured.select_items = items
		captured.select_opts = opts
		captured.select_callback = on_choice
	end

	package.loaded["ai-gitcommit.buffer"] = overrides.buffer or {
		is_gitcommit_buffer = function(bufnr)
			bufnr = bufnr or 0
			return vim.api.nvim_get_option_value("filetype", { buf = bufnr }) == "gitcommit"
		end,
		find_first_comment_line = function(_)
			return 1
		end,
		get_existing_message = function(_)
			return ""
		end,
		is_amend_message_buffer = function(_)
			return false
		end,
	}

	package.loaded["ai-gitcommit.buffer_state"] = overrides.buffer_state or {
		get = function(bufnr)
			states[bufnr] = states[bufnr]
				or {
					generated = false,
					generating = false,
					timer = nil,
					stream_handle = nil,
				}
			return states[bufnr]
		end,
		stop_timer = function(bufnr)
			local state = states[bufnr]
			if state then
				state.timer = nil
			end
		end,
		cancel_stream = function(bufnr)
			local state = states[bufnr]
			if not state then
				return
			end

			if state.stream_handle then
				state.stream_handle.canceled = true
			end

			state.stream_handle = nil
			state.generating = false
		end,
	}

	package.loaded["ai-gitcommit.config"] = overrides.config or {
		validate_provider = function()
			return true, nil
		end,
		get_provider = function()
			return {
				name = "openai",
				config = {
					api_key = "test-key",
					model = "gpt-4o-mini",
					endpoint = "https://example.com/v1/chat/completions",
				},
			}, nil
		end,
		get = function()
			return {
				languages = overrides.languages or { "English" },
				prompt_template = nil,
				context = { max_diff_chars = 15000 },
				filter = { exclude_patterns = {}, include_only = nil },
			}
		end,
	}

	package.loaded["ai-gitcommit.context"] = overrides.context or {
		build_context = function(diff, _)
			return diff
		end,
		filter_files = function(files, _)
			return files
		end,
	}

	package.loaded["ai-gitcommit.git"] = overrides.git or {
		get_staged_diff = function(_, done)
			done("diff --git a/a.lua b/a.lua", nil)
		end,
		get_staged_files = function(_, done)
			done({ { status = "M", file = "a.lua" } }, nil)
		end,
		get_head_diff = function(_, done)
			done("diff --git a/head.lua b/head.lua", nil)
		end,
		get_head_files = function(_, done)
			done({ { status = "M", file = "head.lua" } }, nil)
		end,
	}

	package.loaded["ai-gitcommit.prompt"] = overrides.prompt or {
		build = function(_)
			return "prompt"
		end,
	}

	package.loaded["ai-gitcommit.providers"] = overrides.providers or {
		get = function(_)
			return overrides.provider_impl or {
				resolve_credentials = function(_, done)
					done({ api_key = "test-key" }, nil)
				end,
				generate = function(_, _, _, on_done, _)
					if overrides.auto_finish then
						on_done()
					end

					return { canceled = false }
				end,
			}
		end,
		has_current_credentials = function()
			return true
		end,
	}

	package.loaded["ai-gitcommit.typewriter"] = overrides.typewriter or {
		new = function(opts)
			captured.typewriter_opts = opts
			return {
				push = function(_, _) end,
				finish = function(_, done)
					done()
				end,
				stop = function(_) end,
			}
		end,
	}

	local generator = require("ai-gitcommit.generator")
	local ok, err = xpcall(function()
		callback(generator, {
			notifications = notifications,
			states = states,
			captured = captured,
		})
	end, debug.traceback)

	vim.notify = original_notify
	vim.ui.select = original_select
	for _, name in ipairs(modules) do
		package.loaded[name] = original_loaded[name]
	end

	if not ok then
		error(err)
	end
end

T["generate"] = new_set()

T["generate"]["uses original buffer for deferred language selection"] = function()
	local first_buf = helpers.create_gitcommit_buffer()
	local second_buf = helpers.create_gitcommit_buffer()
	local seen = nil

	with_generator_mocks({ languages = { "English", "中文" } }, function(generator, ctx)
		generator.run = function(language, extra_context, bufnr)
			seen = {
				language = language,
				extra_context = extra_context,
				bufnr = bufnr,
			}
		end

		vim.api.nvim_set_current_buf(first_buf)
		generator.generate("extra context")
		vim.api.nvim_set_current_buf(second_buf)
		ctx.captured.select_callback("中文")
	end)

	helpers.cleanup_buffer(second_buf)
	helpers.cleanup_buffer(first_buf)

	MiniTest.expect.equality(seen.language, "中文")
	MiniTest.expect.equality(seen.extra_context, "extra context")
	MiniTest.expect.equality(seen.bufnr, first_buf)
end

T["run"] = new_set()

T["run"]["returns cleanly for invalid buffer"] = function()
	local bufnr = helpers.create_gitcommit_buffer()
	helpers.cleanup_buffer(bufnr)
	local ok = false

	with_generator_mocks({}, function(generator, ctx)
		ok = pcall(generator.run, "English", nil, bufnr, false)
		MiniTest.expect.equality(#ctx.notifications, 0)
	end)

	MiniTest.expect.equality(ok, true)
end

T["run"]["returns cleanly for unloaded buffer"] = function()
	local bufnr = helpers.create_gitcommit_buffer()
	local other_buf = vim.api.nvim_create_buf(false, true)
	local ok = false

	vim.api.nvim_set_current_buf(other_buf)
	vim.api.nvim_buf_delete(bufnr, { unload = true, force = true })

	with_generator_mocks({}, function(generator, ctx)
		ok = pcall(generator.run, "English", nil, bufnr, false)
		MiniTest.expect.equality(#ctx.notifications, 0)
	end)

	helpers.cleanup_buffer(bufnr)
	helpers.cleanup_buffer(other_buf)

	MiniTest.expect.equality(ok, true)
end

T["run"]["aborts before typewriter writes after user edits"] = function()
	local bufnr = helpers.create_gitcommit_buffer()
	local handle = { canceled = false }
	local before_update = nil

	with_generator_mocks({
		provider_impl = {
			resolve_credentials = function(_, done)
				done({ api_key = "test-key" }, nil)
			end,
			generate = function(_, _, _, _, _)
				return handle
			end,
		},
		typewriter = {
			new = function(opts)
				before_update = opts.before_update
				return {
					push = function(_, _) end,
					finish = function(_, done)
						done()
					end,
					stop = function(_) end,
				}
			end,
		},
	}, function(generator, ctx)
		generator.run("English", nil, bufnr, false)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "user edit" })

		MiniTest.expect.equality(type(before_update), "function")
		MiniTest.expect.equality(before_update(), false)
		MiniTest.expect.equality(handle.canceled, true)
		MiniTest.expect.equality(ctx.states[bufnr].generating, false)
		MiniTest.expect.equality(ctx.notifications[1].msg, "Generating commit message...")
		MiniTest.expect.equality(ctx.notifications[2].msg, "Commit buffer changed during generation")
	end)

	helpers.cleanup_buffer(bufnr)
end

T["run"]["ignores canceled stream errors after state cleanup"] = function()
	local bufnr = helpers.create_gitcommit_buffer()
	local handle = { canceled = false }
	local on_error = nil

	with_generator_mocks({
		provider_impl = {
			resolve_credentials = function(_, done)
				done({ api_key = "test-key" }, nil)
			end,
			generate = function(_, _, _, _, fail)
				on_error = fail
				return handle
			end,
		},
	}, function(generator, ctx)
		generator.run("English", nil, bufnr, false)
		ctx.states[bufnr].stream_handle = nil
		handle.canceled = true
		on_error("ignored")

		MiniTest.expect.equality(#ctx.notifications, 1)
		MiniTest.expect.equality(ctx.notifications[1].msg, "Generating commit message...")
		MiniTest.expect.equality(ctx.states[bufnr].generating, false)
	end)

	helpers.cleanup_buffer(bufnr)
end

return T
