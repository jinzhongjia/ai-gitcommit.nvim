local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

local context

T["setup"] = function()
	context = require("ai-gitcommit.context")
end

T["estimate_tokens"] = new_set()

T["estimate_tokens"]["estimates ~4 chars per token"] = function()
	local tokens = context.estimate_tokens("hello world")
	MiniTest.expect.equality(tokens, 3)
end

T["estimate_tokens"]["handles empty string"] = function()
	local tokens = context.estimate_tokens("")
	MiniTest.expect.equality(tokens, 0)
end

T["should_exclude_file"] = new_set()

T["should_exclude_file"]["returns true for matching pattern"] = function()
	local patterns = { "%.lock$", "%.min%.js$" }
	MiniTest.expect.equality(context.should_exclude_file("yarn.lock", patterns), true)
	MiniTest.expect.equality(context.should_exclude_file("app.min.js", patterns), true)
end

T["should_exclude_file"]["returns false for non-matching pattern"] = function()
	local patterns = { "%.lock$" }
	MiniTest.expect.equality(context.should_exclude_file("main.lua", patterns), false)
end

T["filter_diff"] = new_set()

T["filter_diff"]["removes excluded files from diff"] = function()
	local diff = [[
diff --git a/src/main.lua b/src/main.lua
+local x = 1
diff --git a/package-lock.json b/package-lock.json
+huge json content
diff --git a/src/utils.lua b/src/utils.lua
+local y = 2
]]

	local cfg = {
		filter = {
			exclude_patterns = { "package%-lock%.json$" },
		},
	}

	local filtered = context.filter_diff(diff, cfg)
	MiniTest.expect.equality(filtered:find("package%-lock"), nil)
	MiniTest.expect.equality(filtered:find("main.lua") ~= nil, true)
	MiniTest.expect.equality(filtered:find("utils.lua") ~= nil, true)
end

T["truncate_diff"] = new_set()

T["truncate_diff"]["returns original if under limit"] = function()
	local diff = "short diff"
	local truncated = context.truncate_diff(diff, 1000)
	MiniTest.expect.equality(truncated, diff)
end

T["truncate_diff"]["truncates at newline boundary"] = function()
	local diff = "line1\nline2\nline3\nline4"
	local truncated = context.truncate_diff(diff, 12)
	MiniTest.expect.equality(truncated:find("truncated") ~= nil, true)
end

T["build_context"] = new_set()

T["build_context"]["filters and truncates"] = function()
	local diff = helpers.get_sample_diff()
	local cfg = helpers.get_test_config({
		filter = { exclude_patterns = {} },
		context = { max_diff_chars = 50000 },
	})

	local result = context.build_context(diff, cfg)
	MiniTest.expect.equality(type(result), "string")
	MiniTest.expect.equality(#result > 0, true)
end

return T
