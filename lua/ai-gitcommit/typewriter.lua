local buffer = require("ai-gitcommit.buffer")

local M = {}

---@param bufnr integer
---@return boolean
local function is_buffer_valid(bufnr)
	return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

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
---@field private interval_ms number
---@field private chars_per_tick number
---@field private running boolean
---@field private done_callback? fun()
---@field private before_update? fun(): boolean
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
---@field before_update? fun(): boolean
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
		interval_ms = opts.interval_ms or 12,
		chars_per_tick = opts.chars_per_tick or 4,
		running = false,
		done_callback = nil,
		before_update = opts.before_update,
		on_update = opts.on_update,
	}

	return setmetatable(self, { __index = M })
end

---@param text string
---@return nil
function M:push(text)
	if #text > 0 then
		table.insert(self.queue, text)
		self.queue_len = self.queue_len + #text
		self:_ensure_running()
	end
end

---@return nil
function M:_ensure_running()
	if self.running then
		return
	end
	self.running = true
	self:_schedule_tick()
end

---@return nil
function M:_schedule_tick()
	if not self.running then
		return
	end
	self.timer = vim.defer_fn(function()
		self:_tick()
	end, self.interval_ms)
end

---@return nil
function M:_tick()
	if not self.running or not is_buffer_valid(self.bufnr) then
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
		if not self:_append_chars(new_chars, new_chars_count) then
			self.running = false
			return
		end
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
---@return boolean
function M:_append_chars(chars, count)
	if self.before_update and not self.before_update() then
		return false
	end

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
	return true
end

-- Every call re-detects where the comment lines start via find_first_comment_line,
-- then replaces only [0, first_comment - 1). This keeps git comments untouched
-- regardless of how the message area grows or shrinks across ticks.
-- DO NOT cache first_comment_line — the position shifts as displayed content changes length.
---@return nil
function M:_update_buffer()
	if not is_buffer_valid(self.bufnr) then
		return
	end

	local needs_trailing = #self.displayed > 0 and self.displayed[#self.displayed] ~= ""
	if needs_trailing then
		table.insert(self.displayed, "")
	end

	local first_comment = buffer.find_first_comment_line(self.bufnr)
	vim.api.nvim_buf_set_lines(self.bufnr, 0, first_comment - 1, false, self.displayed)
	if self.on_update then
		self.on_update()
	end

	if needs_trailing then
		table.remove(self.displayed)
	end
end

---@return nil
function M:flush()
	if self.before_update and not self.before_update() then
		self.running = false
		return
	end

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

---@return nil
function M:stop()
	self.running = false
	if self.timer then
		cancel_timer(self.timer)
		self.timer = nil
	end
	self.queue = {}
	self.queue_len = 0
	self.displayed = { "" }
	self.done_callback = nil
end

---@param callback fun()
---@return nil
function M:finish(callback)
	if self.queue_len == 0 and not self.running then
		callback()
		return
	end

	self.done_callback = callback
end

return M
