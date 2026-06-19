local new_set = MiniTest.new_set

local T = new_set()

local git

T["setup"] = function()
	git = require("ai-gitcommit.git")
end


T["get_staged_diff"] = new_set()

T["get_staged_diff"]["returns string"] = function()
	local done = false
	local diff = nil

	git.get_staged_diff(nil, function(result)
		diff = result
		done = true
	end)

	vim.wait(1000, function()
		return done
	end)

	MiniTest.expect.equality(done, true)
	MiniTest.expect.equality(type(diff), "string")
end

T["get_staged_diff"]["returns error when git command fails"] = function()
	local original_system = vim.system
	local done = false
	local diff = nil
	local err = nil

	vim.system = function(_, _, cb)
		cb({ code = 128, stdout = "", stderr = "fatal: not a git repository" })
		return {
			is_closing = function()
				return false
			end,
			kill = function(_, _) end,
		}
	end

	git.get_staged_diff(nil, function(result, result_err)
		diff = result
		err = result_err
		done = true
	end)

	vim.wait(500, function()
		return done
	end)

	vim.system = original_system

	MiniTest.expect.equality(done, true)
	MiniTest.expect.equality(diff, "")
	MiniTest.expect.equality(type(err), "string")
end

T["get_staged_files"] = new_set()

T["get_staged_files"]["returns table"] = function()
	local done = false
	local files = nil

	git.get_staged_files(nil, function(result)
		files = result
		done = true
	end)

	vim.wait(1000, function()
		return done
	end)

	MiniTest.expect.equality(done, true)
	MiniTest.expect.equality(type(files), "table")
end

T["get_staged_files"]["parses status correctly"] = function()
	local done = false
	local files = nil

	git.get_staged_files(nil, function(result)
		files = result
		done = true
	end)

	vim.wait(1000, function()
		return done
	end)

	MiniTest.expect.equality(done, true)
	for _, f in ipairs(files) do
		if f.status then
			MiniTest.expect.equality(type(f.status), "string")
			MiniTest.expect.equality(type(f.file), "string")
		end
	end
end

T["get_staged_files"]["parses rename and copy records from -z output"] = function()
	local original_system = vim.system
	local done = false
	local files = nil

	vim.system = function(_, _, cb)
		cb({
			code = 0,
			stdout = table.concat({
				"R100",
				"old-name.lua",
				"new-name.lua",
				"C100",
				"old-copy.lua",
				"new-copy.lua",
				"M",
				"plain.lua",
			}, "\0") .. "\0",
			stderr = "",
		})
		return {
			is_closing = function()
				return false
			end,
			kill = function(_, _) end,
		}
	end

	git.get_staged_files(nil, function(result)
		files = result
		done = true
	end)

	vim.wait(500, function()
		return done
	end)

	vim.system = original_system

	MiniTest.expect.equality(done, true)
	MiniTest.expect.equality(files[1].status, "R100")
	MiniTest.expect.equality(files[1].file, "old-name.lua -> new-name.lua")
	MiniTest.expect.equality(files[1].old_file, "old-name.lua")
	MiniTest.expect.equality(files[1].new_file, "new-name.lua")
	MiniTest.expect.equality(files[2].status, "C100")
	MiniTest.expect.equality(files[2].old_file, "old-copy.lua")
	MiniTest.expect.equality(files[2].new_file, "new-copy.lua")
	MiniTest.expect.equality(files[3].status, "M")
	MiniTest.expect.equality(files[3].file, "plain.lua")
end

T["get_staged_files"]["returns error when git command fails"] = function()
	local original_system = vim.system
	local done = false
	local files = nil
	local err = nil

	vim.system = function(_, _, cb)
		cb({ code = 128, stdout = "", stderr = "fatal: not a git repository" })
		return {
			is_closing = function()
				return false
			end,
			kill = function(_, _) end,
		}
	end

	git.get_staged_files(nil, function(result, result_err)
		files = result
		err = result_err
		done = true
	end)

	vim.wait(500, function()
		return done
	end)

	vim.system = original_system

	MiniTest.expect.equality(done, true)
	MiniTest.expect.equality(type(files), "table")
	MiniTest.expect.equality(#files, 0)
	MiniTest.expect.equality(type(err), "string")
end

return T
