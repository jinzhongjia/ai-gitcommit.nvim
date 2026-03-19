local new_set = MiniTest.new_set

local T = new_set()

local git

T["setup"] = function()
	git = require("ai-gitcommit.git")
end

T["is_git_repo"] = new_set()

T["is_git_repo"]["returns true in git repository"] = function()
	local done = false
	local result = nil

	git.is_git_repo(function(is_repo)
		result = is_repo
		done = true
	end)

	vim.wait(1000, function()
		return done
	end)

	MiniTest.expect.equality(done, true)
	MiniTest.expect.equality(result, true)
end

T["get_repo_root"] = new_set()

T["get_repo_root"]["returns repo root path"] = function()
	local done = false
	local root = nil

	git.get_repo_root(function(result)
		root = result
		done = true
	end)

	-- Wait for async callback
	vim.wait(1000, function()
		return done
	end)

	MiniTest.expect.equality(root ~= nil, true)
	MiniTest.expect.equality(type(root), "string")
	MiniTest.expect.equality(root:find("ai%-gitcommit") ~= nil, true)
end

T["get_staged_diff"] = new_set()

T["get_staged_diff"]["returns string"] = function()
	local done = false
	local diff = nil

	git.get_staged_diff("normal", function(result)
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
			kill = function(_, _)
			end,
		}
	end

	git.get_staged_diff("normal", function(result, result_err)
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

	git.get_staged_files("normal", function(result)
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

	git.get_staged_files("normal", function(result)
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

T["detect_commit_type"] = new_set()

T["detect_commit_type"]["returns normal for regular commit"] = function()
	local done = false
	local result_type = nil

	git.detect_commit_type(function(commit_type, _)
		result_type = commit_type
		done = true
	end)

	vim.wait(1000, function()
		return done
	end)

	MiniTest.expect.equality(done, true)
	-- In a normal repo with HEAD and no rebase/amend state, should be "normal"
	MiniTest.expect.equality(result_type, "normal")
end

T["detect_commit_type"]["returns normal when not a git repo"] = function()
	local original_system = vim.system
	local done = false
	local result_type = nil

	-- Mock git rev-parse --git-dir to fail
	vim.system = function(cmd, opts, cb)
		if cmd[2] == "rev-parse" and cmd[3] == "--git-dir" then
			cb({ code = 128, stdout = "", stderr = "not a git repo" })
			return {
				is_closing = function()
					return false
				end,
				kill = function(_, _)
				end,
			}
		end
		return original_system(cmd, opts, cb)
	end

	git.detect_commit_type(function(commit_type, _)
		result_type = commit_type
		done = true
	end)

	vim.wait(500, function()
		return done
	end)

	vim.system = original_system

	MiniTest.expect.equality(done, true)
	MiniTest.expect.equality(result_type, "normal")
end

T["get_git_dir"] = new_set()

T["get_git_dir"]["returns git dir path"] = function()
	local done = false
	local result = nil

	git.get_git_dir(function(git_dir)
		result = git_dir
		done = true
	end)

	vim.wait(1000, function()
		return done
	end)

	MiniTest.expect.equality(done, true)
	MiniTest.expect.equality(result ~= nil, true)
	MiniTest.expect.equality(type(result), "string")
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
			kill = function(_, _)
			end,
		}
	end

	git.get_staged_files("normal", function(result, result_err)
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
