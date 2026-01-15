local M = {}

---@class AIGitCommit.Typewriter
---@field private queue string
---@field private displayed string
---@field private timer userdata?
---@field private bufnr number
---@field private on_update fun(text: string, bufnr: number)
---@field private interval_ms number
---@field private chars_per_tick number

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

---@param str string
---@param pos number
---@return string, number
local function extract_utf8_char(str, pos)
	local byte = str:byte(pos)
	if not byte then
		return "", 0
	end
	local len = utf8_char_length(byte)
	if pos + len - 1 > #str then
		return "", 0
	end
	return str:sub(pos, pos + len - 1), len
end

---@class AIGitCommit.TypewriterOpts
---@field bufnr number
---@field on_update fun(text: string, bufnr: number)
---@field interval_ms? number
---@field chars_per_tick? number

---@param opts AIGitCommit.TypewriterOpts
---@return AIGitCommit.Typewriter
function M.new(opts)
	local self = {
		queue = "",
		displayed = "",
		timer = nil,
		bufnr = opts.bufnr,
		on_update = opts.on_update,
		interval_ms = opts.interval_ms or 10,
		chars_per_tick = opts.chars_per_tick or 3,
	}

	return setmetatable(self, { __index = M })
end

---@param text string
function M:push(text)
	self.queue = self.queue .. text
	self:_start_timer()
end

function M:_start_timer()
	if self.timer then
		return
	end

	self.timer = vim.defer_fn(function()
		self:_tick()
	end, self.interval_ms)
end

function M:_tick()
	self.timer = nil

	if #self.queue == 0 then
		return
	end

	if not vim.api.nvim_buf_is_valid(self.bufnr) then
		self.queue = ""
		return
	end

	local chars_added = 0
	local pos = 1

	while chars_added < self.chars_per_tick and pos <= #self.queue do
		local char, len = extract_utf8_char(self.queue, pos)
		if len == 0 then
			break
		end
		self.displayed = self.displayed .. char
		pos = pos + len
		chars_added = chars_added + 1
	end

	self.queue = self.queue:sub(pos)

	vim.schedule(function()
		if vim.api.nvim_buf_is_valid(self.bufnr) then
			self.on_update(self.displayed, self.bufnr)
		end
	end)

	if #self.queue > 0 then
		self:_start_timer()
	end
end

function M:flush()
	if self.timer then
		pcall(function()
			self.timer:stop()
			self.timer:close()
		end)
		self.timer = nil
	end

	if #self.queue > 0 then
		self.displayed = self.displayed .. self.queue
		self.queue = ""

		if vim.api.nvim_buf_is_valid(self.bufnr) then
			self.on_update(self.displayed, self.bufnr)
		end
	end
end

function M:stop()
	if self.timer then
		pcall(function()
			self.timer:stop()
			self.timer:close()
		end)
		self.timer = nil
	end
	self.queue = ""
	self.displayed = ""
end

---@return string
function M:get_displayed()
	return self.displayed
end

return M
