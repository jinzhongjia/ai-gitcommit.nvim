local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

local context

T["setup"] = function()
	context = require("ai-gitcommit.context")
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

T["filter_diff"]["respects path patterns in exclude_patterns"] = function()
	local diff = [[
diff --git a/src/main.lua b/src/main.lua
+local x = 1
diff --git a/vendor/lib.lua b/vendor/lib.lua
+local ignored = true
]]

	local cfg = {
		filter = {
			exclude_patterns = { "^vendor/" },
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
			include_only = { "^lua/" },
		},
	}

	local filtered = context.filter_diff(diff, cfg)
	MiniTest.expect.equality(filtered:find("lua/a.lua", 1, true) ~= nil, true)
	MiniTest.expect.equality(filtered:find("tests/a.lua", 1, true), nil)
end

T["filter_diff"]["decodes Git quoted paths before applying filters"] = function()
	local excluded = 'diff --git "a/vendor/caf\\303\\251.lua" "b/vendor/caf\\303\\251.lua"\n+excluded\n'
	local kept = 'diff --git "a/src/line\\t\\"name.lua" "b/src/line\\t\\"name.lua"\n+kept\n'
	local diff = excluded .. kept
	local cfg = {
		filter = {
			exclude_patterns = { "^vendor/" },
			include_only = { '^src/line\t"name%.lua$', "^vendor/" },
		},
	}

	MiniTest.expect.equality(context.filter_diff(diff, cfg), kept)
end

T["filter_diff"]["resets filtering at a quoted header following an excluded file"] = function()
	local excluded = "diff --git a/vendor/plain.lua b/vendor/plain.lua\n+excluded\n"
	local kept = 'diff --git "a/caf\\303\\251.lua" "b/caf\\303\\251.lua"\n+kept\n'
	local cfg = { filter = { exclude_patterns = { "^vendor/" }, include_only = { "^café%.lua$" } } }

	MiniTest.expect.equality(context.filter_diff(excluded .. kept, cfg), kept)
end

T["filter_diff"]["handles renames with one quoted path"] = function()
	local old_quoted = 'diff --git "a/old\\tname.lua" b/new.lua\n+old quoted\n'
	local new_quoted = 'diff --git a/old.lua "b/new\\tname.lua"\n+new quoted\n'
	local cfg = { filter = { include_only = { "^new\tname%.lua$" } } }

	MiniTest.expect.equality(context.filter_diff(old_quoted .. new_quoted, cfg), new_quoted)
end

T["filter_files"] = new_set()

T["filter_files"]["keeps rename when old or new path matches"] = function()
	local files = {
		{
			status = "R100",
			file = "old/path.lua -> new/path.lua",
			old_file = "old/path.lua",
			new_file = "new/path.lua",
		},
		{
			status = "R100",
			file = "old/skip.lua -> new/skip.lua",
			old_file = "old/skip.lua",
			new_file = "new/skip.lua",
		},
	}
	local cfg = {
		filter = {
			exclude_patterns = { "^old/skip" },
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
