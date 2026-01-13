local uv = vim.uv

local M = {}

---@class AIGitCommit.StreamRequest
---@field url string
---@field method? string
---@field headers? table<string, string>
---@field body? table|string

---@class AIGitCommit.StreamHandle
---@field handle userdata
---@field stdout userdata
---@field stderr userdata

---@param opts AIGitCommit.StreamRequest
---@param on_chunk fun(chunk: table)
---@param on_done fun()
---@param on_error fun(err: string)
---@return AIGitCommit.StreamHandle?
function M.request(opts, on_chunk, on_done, on_error)
	local args = { "-s", "-N", "-X", opts.method or "POST" }

	for key, value in pairs(opts.headers or {}) do
		table.insert(args, "-H")
		table.insert(args, key .. ": " .. value)
	end

	if opts.body then
		table.insert(args, "-d")
		local body_str = type(opts.body) == "table" and vim.json.encode(opts.body) or opts.body
		table.insert(args, body_str)
	end

	table.insert(args, opts.url)

	local stdout = uv.new_pipe()
	local stderr = uv.new_pipe()
	local stderr_chunks = {}
	local stdout_buffer = ""

	local handle, pid = uv.spawn("curl", {
		args = args,
		stdio = { nil, stdout, stderr },
	}, function(code)
		stdout:close()
		stderr:close()

		vim.schedule(function()
			if code == 0 then
				on_done()
			else
				local err_msg = #stderr_chunks > 0 and table.concat(stderr_chunks, "") or "Request failed"
				on_error(err_msg)
			end
		end)
	end)

	if not handle then
		on_error("Failed to spawn curl")
		return nil
	end

	stdout:read_start(function(err, data)
		if err then
			vim.schedule(function()
				on_error(err)
			end)
			return
		end

		if data then
			stdout_buffer = stdout_buffer .. data
			local lines = vim.split(stdout_buffer, "\n", { plain = true })
			stdout_buffer = lines[#lines]

			for i = 1, #lines - 1 do
				local line = lines[i]
				if line:match("^data: ") then
					local json_str = line:sub(7)
					if json_str ~= "[DONE]" then
						local ok, chunk = pcall(vim.json.decode, json_str)
						if ok and chunk then
							vim.schedule(function()
								on_chunk(chunk)
							end)
						end
					end
				elseif line ~= "" and not line:match("^event: ") then
					local ok, chunk = pcall(vim.json.decode, line)
					if ok and chunk and chunk.error then
						vim.schedule(function()
							on_error(chunk.error.message or "API error")
						end)
					end
				end
			end
		end
	end)

	stderr:read_start(function(err, data)
		if data then
			table.insert(stderr_chunks, data)
		end
	end)

	return { handle = handle, stdout = stdout, stderr = stderr }
end

---@param stream_handle AIGitCommit.StreamHandle?
function M.cancel(stream_handle)
	if stream_handle then
		if stream_handle.handle and not stream_handle.handle:is_closing() then
			stream_handle.handle:kill("sigterm")
		end
	end
end

return M
