local M = {}

---@param timer userdata
local function cancel_timer(timer)
	pcall(function()
		timer:stop()
		timer:close()
	end)
end

---@class AIGitCommit.Typewriter
---@field private queue string[]
---@field private queue_len number
---@field private displayed string[]
---@field private timer userdata?
---@field private bufnr number
---@field private first_comment_line number
---@field private written_lines number
---@field private interval_ms number
---@field private chars_per_tick number
---@field private running boolean
---@field private done_callback? fun()
---@field private on_update? fun()

---@param byte number
---@return number
local function utf8_char_length(byte)
	if byte < 0x80 then
		return 1
	elseif byte < 0xE0 then
		return 2
	elseif byte < 0xF0 then
		return 3
	else
		return 4
	end
end

---@class AIGitCommit.TypewriterOpts
---@field bufnr number
---@field first_comment_line number
---@field interval_ms? number
---@field chars_per_tick? number
---@field on_update? fun()

---@param opts AIGitCommit.TypewriterOpts
---@return AIGitCommit.Typewriter
function M.new(opts)
	local self = {
		queue = {},
		queue_len = 0,
		displayed = { "" },
		timer = nil,
		bufnr = opts.bufnr,
		first_comment_line = opts.first_comment_line,
		written_lines = 0,
		interval_ms = opts.interval_ms or 12,
		chars_per_tick = opts.chars_per_tick or 4,
		running = false,
		done_callback = nil,
		on_update = opts.on_update,
	}

	return setmetatable(self, { __index = M })
end

---@param text string
function M:push(text)
	if #text > 0 then
		table.insert(self.queue, text)
		self.queue_len = self.queue_len + #text
		self:_ensure_running()
	end
end

function M:_ensure_running()
	if self.running then
		return
	end
	self.running = true
	self:_schedule_tick()
end

function M:_schedule_tick()
	if not self.running then
		return
	end
	self.timer = vim.defer_fn(function()
		self:_tick()
	end, self.interval_ms)
end

function M:_tick()
	if not self.running or not vim.api.nvim_buf_is_valid(self.bufnr) then
		self.running = false
		return
	end

	local chars_processed = 0
	local new_chars = {}
	local new_chars_count = 0

	while chars_processed < self.chars_per_tick and #self.queue > 0 do
		local chunk = self.queue[1]
		local pos = 1

		while pos <= #chunk and chars_processed < self.chars_per_tick do
			local byte = chunk:byte(pos)
			local len = utf8_char_length(byte)

			if pos + len - 1 <= #chunk then
				new_chars_count = new_chars_count + 1
				new_chars[new_chars_count] = chunk:sub(pos, pos + len - 1)
				pos = pos + len
				chars_processed = chars_processed + 1
			else
				break
			end
		end

		if pos > #chunk then
			table.remove(self.queue, 1)
		else
			self.queue[1] = chunk:sub(pos)
		end
		self.queue_len = self.queue_len - (pos - 1)
	end

	if new_chars_count > 0 then
		self:_append_chars(new_chars, new_chars_count)
	end

	if self.queue_len > 0 then
		self:_schedule_tick()
	else
		self.running = false
		if self.done_callback then
			local cb = self.done_callback
			self.done_callback = nil
			cb()
		end
	end
end

---@param chars string[]
---@param count number
function M:_append_chars(chars, count)
	for i = 1, count do
		local char = chars[i]
		if char == "\n" then
			table.insert(self.displayed, "")
		else
			local last_idx = #self.displayed
			self.displayed[last_idx] = self.displayed[last_idx] .. char
		end
	end

	self:_update_buffer()
end

function M:_update_buffer()
	if not vim.api.nvim_buf_is_valid(self.bufnr) then
		return
	end

	local needs_trailing = #self.displayed > 0 and self.displayed[#self.displayed] ~= ""
	if needs_trailing then
		table.insert(self.displayed, "")
	end

	local delete_to = math.max(self.written_lines, self.first_comment_line - 1)
	vim.api.nvim_buf_set_lines(self.bufnr, 0, delete_to, false, self.displayed)
	self.written_lines = #self.displayed
	if self.on_update then
		self.on_update()
	end

	if needs_trailing then
		table.remove(self.displayed)
	end
end

function M:flush()
	self.running = false
	if self.timer then
		cancel_timer(self.timer)
		self.timer = nil
	end

	for _, chunk in ipairs(self.queue) do
		local pos = 1
		while pos <= #chunk do
			local byte = chunk:byte(pos)
			local len = utf8_char_length(byte)
			local char = chunk:sub(pos, pos + len - 1)
			if char == "\n" then
				table.insert(self.displayed, "")
			else
				local last_idx = #self.displayed
				self.displayed[last_idx] = self.displayed[last_idx] .. char
			end
			pos = pos + len
		end
	end
	self.queue = {}
	self.queue_len = 0

	self:_update_buffer()
end

function M:stop()
	self.running = false
	if self.timer then
		cancel_timer(self.timer)
		self.timer = nil
	end
	self.queue = {}
	self.queue_len = 0
	self.displayed = { "" }
	self.written_lines = 0
	self.done_callback = nil
end

---@param callback fun()
function M:finish(callback)
	if self.queue_len == 0 and not self.running then
		callback()
		return
	end

	self.done_callback = callback
end

return M
