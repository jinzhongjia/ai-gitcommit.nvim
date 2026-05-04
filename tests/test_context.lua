local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

local context

T["setup"] = function()
	context = require("ai-gitcommit.context")
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

T["filter_diff"]["respects exclude_paths"] = function()
	local diff = [[
diff --git a/src/main.lua b/src/main.lua
+local x = 1
diff --git a/vendor/lib.lua b/vendor/lib.lua
+local ignored = true
]]

	local cfg = {
		filter = {
			exclude_patterns = {},
			exclude_paths = { "^vendor/" },
			include_only = nil,
		},
	}

	local filtered = context.filter_diff(diff, cfg)
	MiniTest.expect.equality(filtered:find("vendor/lib.lua", 1, true), nil)
	MiniTest.expect.equality(filtered:find("src/main.lua", 1, true) ~= nil, true)
end

T["filter_diff"]["respects include_only"] = function()
	local diff = [[
diff --git a/lua/a.lua b/lua/a.lua
+local a = true
diff --git a/tests/a.lua b/tests/a.lua
+local b = true
]]

	local cfg = {
		filter = {
			exclude_patterns = {},
			exclude_paths = {},
			include_only = { "^lua/" },
		},
	}

	local filtered = context.filter_diff(diff, cfg)
	MiniTest.expect.equality(filtered:find("lua/a.lua", 1, true) ~= nil, true)
	MiniTest.expect.equality(filtered:find("tests/a.lua", 1, true), nil)
end

T["filter_files"] = new_set()

T["filter_files"]["keeps rename when old or new path matches"] = function()
	local files = {
		{ status = "R100", file = "old/path.lua -> new/path.lua", old_file = "old/path.lua", new_file = "new/path.lua" },
		{ status = "R100", file = "old/skip.lua -> new/skip.lua", old_file = "old/skip.lua", new_file = "new/skip.lua" },
	}
	local cfg = {
		filter = {
			exclude_patterns = {},
			exclude_paths = { "^old/skip" },
			include_only = { "^new/", "^old/path" },
		},
	}

	local filtered = context.filter_files(files, cfg)
	MiniTest.expect.equality(#filtered, 2)
	MiniTest.expect.equality(filtered[1].old_file, "old/path.lua")
	MiniTest.expect.equality(filtered[1].new_file, "new/path.lua")
	MiniTest.expect.equality(filtered[2].old_file, "old/skip.lua")
	MiniTest.expect.equality(filtered[2].new_file, "new/skip.lua")
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

T["truncate_diff"]["truncates by max lines"] = function()
	local diff = "line1\nline2\nline3\nline4"
	local truncated = context.truncate_diff_lines(diff, 2)
	MiniTest.expect.equality(truncated:find("line1", 1, true) ~= nil, true)
	MiniTest.expect.equality(truncated:find("line3", 1, true), nil)
	MiniTest.expect.equality(truncated:find("line limit", 1, true) ~= nil, true)
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
