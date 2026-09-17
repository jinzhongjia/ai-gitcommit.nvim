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
		if has_error or (handle and handle.canceled) then
			return
		end

		if chunk.type == "error" or chunk.error then
			has_error = true
			local err = chunk.error
			local message = type(err) == "table" and err.message or err
			if type(message) ~= "string" then
				message = type(chunk.message) == "string" and chunk.message or "API error"
			end
			vim.schedule(function()
				if not handle.canceled then
					on_error(message)
				end
			end)
			return
		end

		vim.schedule(function()
			if not handle.canceled then
				on_chunk(chunk)
			end
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
		if ok and type(chunk) == "table" then
			parsed_chunk_count = parsed_chunk_count + 1
			handle_chunk(chunk)
		else
			decode_error_count = decode_error_count + 1
		end
	end

	---@param line string
	local function process_line(line)
		line = line:gsub("\r$", "")
		if line == "" then
			flush_sse_event()
		elseif line:match("^data:") then
			local json_str = line:gsub("^data:%s?", "")
			table.insert(sse_data_lines, json_str)
		elseif line ~= "" and not line:match("^event:") then
			local ok, chunk = pcall(vim.json.decode, line)
			if ok and type(chunk) == "table" then
				parsed_chunk_count = parsed_chunk_count + 1
				handle_chunk(chunk)
			else
				decode_error_count = decode_error_count + 1
			end
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
			process_line(lines[i])
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
		if stdout_buffer ~= "" then
			process_line(stdout_buffer)
			stdout_buffer = ""
		end
		flush_sse_event()

		vim.schedule(function()
			if handle.canceled then
				return
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
				if ok and type(data) == "table" and data.error then
					local err = data.error
					local message = type(err) == "table" and err.message or err
					on_error(type(message) == "string" and message or "API error")
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
