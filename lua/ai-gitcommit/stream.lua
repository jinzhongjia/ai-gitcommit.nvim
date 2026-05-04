local M = {}

---@class AIGitCommit.StreamRequest
---@field url string
---@field method? string
---@field headers? table<string, string>
---@field body? table|string

---@class AIGitCommit.StreamHandle
---@field system_obj vim.SystemObj
---@field canceled boolean

---@param opts AIGitCommit.StreamRequest
---@param on_chunk fun(chunk: table)
---@param on_done fun()
---@param on_error fun(err: string)
---@return AIGitCommit.StreamHandle?
function M.request(opts, on_chunk, on_done, on_error)
	local args = { "curl", "-s", "-S", "-N", "-X", opts.method or "POST", "--fail-with-body" }

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

	local stderr_chunks = {}
	local stdout_chunks = {}
	local stdout_buffer = ""
	local has_error = false
	local parsed_chunk_count = 0
	local decode_error_count = 0
	local sse_data_lines = {}
	---@type AIGitCommit.StreamHandle
	local handle

	---@param chunk table
	local function handle_chunk(chunk)
		if chunk.type == "error" and chunk.error then
			has_error = true
			vim.schedule(function()
				on_error(chunk.error.message or "API error")
			end)
			return
		end

		if chunk.error then
			has_error = true
			vim.schedule(function()
				on_error(chunk.error.message or chunk.error or "API error")
			end)
			return
		end

		vim.schedule(function()
			on_chunk(chunk)
		end)
	end

	local function flush_sse_event()
		if #sse_data_lines == 0 then
			return
		end

		local payload = table.concat(sse_data_lines, "\n")
		sse_data_lines = {}

		if payload == "[DONE]" or payload == "" then
			return
		end

		local ok, chunk = pcall(vim.json.decode, payload)
		if ok and chunk then
			parsed_chunk_count = parsed_chunk_count + 1
			handle_chunk(chunk)
		else
			decode_error_count = decode_error_count + 1
		end
	end

	---@param data string?
	local function process_stdout(_, data)
		if not data then
			return
		end

		table.insert(stdout_chunks, data)
		stdout_buffer = stdout_buffer .. data
		local lines = vim.split(stdout_buffer, "\n", { plain = true })
		stdout_buffer = lines[#lines]

		for i = 1, #lines - 1 do
			local line = lines[i]:gsub("\r$", "")
			if line == "" then
				flush_sse_event()
			elseif line:match("^data:") then
				local json_str = line:gsub("^data:%s?", "")
				table.insert(sse_data_lines, json_str)
			elseif line ~= "" and not line:match("^event:") then
				local ok, chunk = pcall(vim.json.decode, line)
				if ok and chunk then
					parsed_chunk_count = parsed_chunk_count + 1
					handle_chunk(chunk)
				else
					decode_error_count = decode_error_count + 1
				end
			end
		end
	end

	---@param data string?
	local function process_stderr(_, data)
		if data then
			table.insert(stderr_chunks, data)
		end
	end

	local system_obj = vim.system(args, {
		stdout = process_stdout,
		stderr = process_stderr,
	}, function(obj)
		vim.schedule(function()
			if handle.canceled then
				return
			end

			if #sse_data_lines > 0 then
				flush_sse_event()
			end

			if has_error then
				return
			end
			if obj.code == 0 then
				if parsed_chunk_count == 0 and decode_error_count > 0 then
					has_error = true
					on_error("Failed to parse streaming response")
					return
				end

				on_done()
			else
				local stdout_full = table.concat(stdout_chunks, "")
				local ok, data = pcall(vim.json.decode, stdout_full)
				if ok and data and data.error then
					on_error(data.error.message or "API error")
				elseif vim.trim(stdout_full) ~= "" then
					on_error(vim.trim(stdout_full))
				else
					local err_msg = #stderr_chunks > 0 and table.concat(stderr_chunks, "")
						or "Request failed (HTTP error)"
					on_error(err_msg)
				end
			end
		end)
	end)

	handle = { system_obj = system_obj, canceled = false }
	return handle
end

---@param stream_handle AIGitCommit.StreamHandle?
function M.cancel(stream_handle)
	if stream_handle and stream_handle.system_obj then
		stream_handle.canceled = true
		if not stream_handle.system_obj:is_closing() then
			stream_handle.system_obj:kill("sigterm")
		end
	end
end

return M
