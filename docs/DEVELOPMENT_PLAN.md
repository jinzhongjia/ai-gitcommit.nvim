# ai-gitcommit.nvim Development Plan

> Neovim plugin for AI-powered git commit message generation

## Overview

| Item | Decision |
|------|----------|
| **Neovim Version** | 0.11+ |
| **External Dependencies** | None (only `curl` command) |
| **Streaming** | Supported |
| **Providers** | OpenAI / Anthropic / GitHub Copilot |
| **OAuth Support** | GitHub Copilot, OpenAI Codex, Claude Code (reserved) |
| **Command** | `:AICommit [extra context]` |
| **Multi-language** | Supported (configurable output language) |

---

## Project Structure

```
ai-gitcommit.nvim/
├── lua/
│   └── ai-gitcommit/
│       ├── init.lua              # setup() + generate() + commands
│       ├── config.lua            # Configuration management
│       ├── git.lua               # Git operations (diff/status)
│       ├── buffer.lua            # Buffer read/write
│       ├── context.lua           # Diff filtering/truncation
│       ├── prompt.lua            # Prompt templates (multi-language)
│       ├── stream.lua            # Streaming HTTP requests
│       ├── auth/
│       │   ├── init.lua          # Auth module entry point
│       │   ├── copilot.lua       # GitHub Copilot OAuth (Device Flow)
│       │   ├── codex.lua         # OpenAI Codex OAuth (reserved)
│       │   └── claude.lua        # Claude Code OAuth (reserved)
│       └── providers/
│           ├── init.lua          # Provider factory
│           ├── openai.lua        # OpenAI API implementation
│           ├── anthropic.lua     # Anthropic API implementation
│           └── copilot.lua       # GitHub Copilot implementation
├── plugin/
│   └── ai-gitcommit.lua          # Auto-load
├── doc/
│   └── ai-gitcommit.txt          # Vimdoc help
└── README.md
```

---

## Configuration Example

```lua
require("ai-gitcommit").setup({
  -- Current provider
  provider = "openai",  -- "openai" | "anthropic" | "copilot"
  
  -- Provider configurations
  providers = {
    openai = {
      -- Authentication: API key or OAuth (Codex)
      api_key = vim.env.OPENAI_API_KEY,  -- or function / cmd
      -- oauth = true,  -- (reserved) use Codex OAuth instead of API key
      model = "gpt-4o-mini",
      endpoint = "https://api.openai.com/v1/chat/completions",
      max_tokens = 500,
    },
    anthropic = {
      -- Authentication: API key or OAuth (Claude Code)
      api_key = vim.env.ANTHROPIC_API_KEY,
      -- oauth = true,  -- (reserved) use Claude Code OAuth instead of API key
      model = "claude-3-5-sonnet-20241022",
      endpoint = "https://api.anthropic.com/v1/messages",
      max_tokens = 500,
    },
    copilot = {
      -- GitHub Copilot uses OAuth Device Flow (no API key needed)
      -- Token stored in ~/.config/github-copilot/
      model = "gpt-4o",  -- or other Copilot-supported models
    },
  },
  
  -- Output language
  language = "English",  -- English / Chinese / Japanese / Korean / ...
  
  -- Commit style
  commit_style = "conventional",  -- conventional / simple / detailed
  
  -- Context limits
  context = {
    max_diff_lines = 500,
    max_diff_chars = 15000,
  },
  
  -- File filtering
  filter = {
    exclude_patterns = {
      "%.lock$",
      "package%-lock%.json$",
      "yarn%.lock$",
      "pnpm%-lock%.yaml$",
      "%.min%.[jc]ss?$",
    },
  },
  
  -- Keymap (optional)
  keymap = "<leader>gc",
})
```

---

## Command Design

```lua
-- :AICommit [extra context]
vim.api.nvim_create_user_command("AICommit", function(opts)
  local extra_context = opts.args ~= "" and opts.args or nil
  require("ai-gitcommit").generate(extra_context)
end, {
  nargs = "*",
  desc = "Generate commit message using AI",
})
```

**Usage:**
```vim
:AICommit                          " Generate directly
:AICommit fix typo in readme       " With extra context
:AICommit refactored auth module   " Description hint
```

---

## Core Module Specifications

### 1. config.lua - Configuration Management

**Responsibilities:**
- Merge user config with defaults
- Validate configuration
- Provide config access API

**Key Functions:**
```lua
M.setup(opts)           -- Initialize config
M.get()                 -- Get current config
M.get_provider()        -- Get current provider config
M.get_api_key(provider) -- Get API key (env / function / cmd)
```

**API Key Resolution (4-tier priority):**
```lua
local function get_api_key(config)
  -- 1. Environment variable
  if vim.env[config.api_key_env] then
    return vim.env[config.api_key_env]
  end
  -- 2. Function return
  if type(config.api_key) == "function" then
    return config.api_key()
  end
  -- 3. Direct value
  if type(config.api_key) == "string" then
    return config.api_key
  end
  -- 4. Command execution (e.g., `pass show openai/api_key`)
  if config.api_key_cmd then
    local result = vim.system(config.api_key_cmd, { text = true }):wait()
    return vim.trim(result.stdout)
  end
  return nil
end
```

---

### 2. git.lua - Git Operations

**Responsibilities:**
- Get staged diff
- Get staged file list
- Check if in git repository

**Key Functions:**
```lua
M.get_staged_diff(callback)    -- Get `git diff --cached`
M.get_staged_files(callback)   -- Get staged file list with status
M.is_git_repo()                -- Check if current dir is git repo
M.get_repo_root(callback)      -- Get repository root path
```

**Implementation:**
```lua
function M.get_staged_diff(callback)
  vim.system({ "git", "diff", "--cached" }, { text = true }, function(result)
    vim.schedule(function()
      callback(result.stdout or "")
    end)
  end)
end

function M.get_staged_files(callback)
  vim.system({ "git", "diff", "--cached", "--name-status" }, { text = true }, function(result)
    vim.schedule(function()
      local files = {}
      for line in (result.stdout or ""):gmatch("[^\n]+") do
        local status, file = line:match("^(%S+)%s+(.+)$")
        if status and file then
          table.insert(files, { status = status, file = file })
        end
      end
      callback(files)
    end)
  end)
end
```

---

### 3. stream.lua - Streaming HTTP Requests

**Responsibilities:**
- Send HTTP requests with streaming support
- Parse SSE (Server-Sent Events) format
- Handle chunked responses

**Key Functions:**
```lua
M.request(opts, on_chunk, on_done, on_error)
```

**Implementation:**
```lua
local M = {}

function M.request(opts, on_chunk, on_done, on_error)
  local args = {
    "curl", "-s", "-N",  -- -N: no buffer for streaming
    "-X", opts.method or "POST",
  }
  
  -- Headers
  for key, value in pairs(opts.headers or {}) do
    table.insert(args, "-H")
    table.insert(args, key .. ": " .. value)
  end
  
  -- Body
  if opts.body then
    table.insert(args, "-d")
    table.insert(args, type(opts.body) == "table" and vim.json.encode(opts.body) or opts.body)
  end
  
  table.insert(args, opts.url)
  
  local buffer = ""
  
  vim.fn.jobstart(args, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        buffer = buffer .. line
        -- Parse SSE format: "data: {...}"
        if line:match("^data: ") then
          local json_str = line:sub(7)
          if json_str == "[DONE]" then
            -- OpenAI stream end signal
          else
            local ok, chunk = pcall(vim.json.decode, json_str)
            if ok then
              vim.schedule(function()
                on_chunk(chunk)
              end)
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      local err = table.concat(data, "\n")
      if err ~= "" then
        vim.schedule(function()
          on_error(err)
        end)
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          on_done()
        else
          on_error("Request failed with code: " .. code)
        end
      end)
    end,
  })
end

return M
```

---

### 4. providers/openai.lua - OpenAI Provider

**API Format:**
```lua
-- Request
{
  model = "gpt-4o-mini",
  messages = {
    { role = "user", content = "..." }
  },
  max_tokens = 500,
  temperature = 0.3,
  stream = true,
}

-- Streaming Response (SSE)
data: {"choices":[{"delta":{"content":"feat"}}]}
data: {"choices":[{"delta":{"content":"(auth)"}}]}
data: [DONE]
```

**Implementation:**
```lua
local stream = require("ai-gitcommit.stream")

local M = {}

function M.generate(prompt, config, on_chunk, on_done, on_error)
  local body = {
    model = config.model,
    messages = {
      { role = "user", content = prompt }
    },
    max_tokens = config.max_tokens,
    temperature = 0.3,
    stream = true,
  }
  
  stream.request({
    url = config.endpoint,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. config.api_key,
    },
    body = body,
  }, function(chunk)
    -- Extract content from OpenAI streaming format
    local content = chunk.choices and chunk.choices[1] 
      and chunk.choices[1].delta and chunk.choices[1].delta.content
    if content then
      on_chunk(content)
    end
  end, on_done, on_error)
end

return M
```

---

### 5. providers/anthropic.lua - Anthropic Provider

**API Format:**
```lua
-- Request
{
  model = "claude-3-5-sonnet-20241022",
  max_tokens = 500,
  messages = {
    { role = "user", content = "..." }
  },
  stream = true,
}

-- Streaming Response (SSE)
event: content_block_delta
data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"feat"}}

event: message_stop
data: {"type":"message_stop"}
```

**Implementation:**
```lua
local stream = require("ai-gitcommit.stream")

local M = {}

function M.generate(prompt, config, on_chunk, on_done, on_error)
  local body = {
    model = config.model,
    max_tokens = config.max_tokens,
    messages = {
      { role = "user", content = prompt }
    },
    stream = true,
  }
  
  stream.request({
    url = config.endpoint,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["x-api-key"] = config.api_key,
      ["anthropic-version"] = "2023-06-01",
    },
    body = body,
  }, function(chunk)
    -- Extract content from Anthropic streaming format
    if chunk.type == "content_block_delta" and chunk.delta then
      local text = chunk.delta.text
      if text then
        on_chunk(text)
      end
    end
  end, on_done, on_error)
end

return M
```

---

### 6. buffer.lua - Buffer Operations

**Responsibilities:**
- Check if current buffer is gitcommit
- Find comment line position
- Set commit message (preserve comments)

**Key Functions:**
```lua
M.is_gitcommit_buffer(bufnr)      -- Check filetype
M.find_first_comment_line(bufnr)  -- Find "# ..." line
M.set_commit_message(msg, bufnr)  -- Replace message area
M.get_current_message(bufnr)      -- Get existing message
```

**Implementation:**
```lua
local M = {}

function M.is_gitcommit_buffer(bufnr)
  bufnr = bufnr or 0
  return vim.bo[bufnr].filetype == "gitcommit"
end

function M.find_first_comment_line(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match("^#") then
      return i  -- 1-indexed
    end
  end
  return #lines + 1
end

function M.set_commit_message(message, bufnr)
  bufnr = bufnr or 0
  local first_comment = M.find_first_comment_line(bufnr)
  local message_lines = vim.split(message, "\n")
  
  -- Ensure empty line after message
  if #message_lines > 0 and message_lines[#message_lines] ~= "" then
    table.insert(message_lines, "")
  end
  
  -- Replace content before comments
  vim.api.nvim_buf_set_lines(bufnr, 0, first_comment - 1, false, message_lines)
  
  -- Move cursor to first line
  local win = vim.fn.bufwinid(bufnr)
  if win ~= -1 then
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
  end
end

return M
```

---

### 7. context.lua - Diff Filtering/Truncation

**Responsibilities:**
- Filter out unwanted files (lock files, minified, etc.)
- Truncate diff to fit context window
- Estimate token count

**Key Functions:**
```lua
M.filter_diff(diff, files, config)   -- Apply filters
M.truncate_diff(diff, max_chars)     -- Smart truncation
M.estimate_tokens(text)              -- Token estimation
M.build_context(diff, files, config) -- Build final context
```

**Implementation:**
```lua
local M = {}

function M.estimate_tokens(text)
  -- Heuristic: 1 token ≈ 4 characters
  return math.ceil(#text / 4)
end

function M.should_exclude_file(filename, patterns)
  for _, pattern in ipairs(patterns) do
    if filename:match(pattern) then
      return true
    end
  end
  return false
end

function M.filter_diff(diff, config)
  local patterns = config.filter.exclude_patterns or {}
  local lines = vim.split(diff, "\n")
  local result = {}
  local current_file = nil
  local skip_file = false
  
  for _, line in ipairs(lines) do
    -- Detect file header: "diff --git a/path b/path"
    local file = line:match("^diff %-%-git a/(.-) b/")
    if file then
      current_file = file
      skip_file = M.should_exclude_file(file, patterns)
    end
    
    if not skip_file then
      table.insert(result, line)
    end
  end
  
  return table.concat(result, "\n")
end

function M.truncate_diff(diff, max_chars)
  if #diff <= max_chars then
    return diff
  end
  
  -- Truncate with notice
  local truncated = diff:sub(1, max_chars)
  -- Find last complete line
  local last_newline = truncated:match(".*\n()")
  if last_newline then
    truncated = truncated:sub(1, last_newline - 1)
  end
  
  return truncated .. "\n\n[... diff truncated due to size limit ...]"
end

function M.build_context(diff, files, config)
  local filtered = M.filter_diff(diff, config)
  local truncated = M.truncate_diff(filtered, config.context.max_diff_chars)
  return truncated
end

return M
```

---

### 8. prompt.lua - Prompt Templates

**Responsibilities:**
- Build prompt from template
- Support multiple languages
- Support different commit styles

**Implementation:**
```lua
local M = {}

M.templates = {
  conventional = [[
Generate a git commit message for the following changes.

Requirements:
- Follow Conventional Commits format: type(scope): description
- Types: feat, fix, docs, style, refactor, test, chore, perf, ci, build
- Keep the subject line under 72 characters
- Write in {language}
- Be concise but descriptive
- Focus on WHY the change was made, not just WHAT changed

{extra_context}

Staged files:
{staged_files}

Diff:
```diff
{diff}
```

Respond with ONLY the commit message, no explanation or markdown formatting.
]],

  simple = [[
Generate a simple git commit message for these changes.
Write in {language}. Keep it under 72 characters.

{extra_context}

Changes:
{staged_files}

Diff:
```diff
{diff}
```

Respond with ONLY the commit message.
]],
}

function M.build(opts)
  local template = M.templates[opts.style] or M.templates.conventional
  
  local staged_files_str = ""
  for _, file in ipairs(opts.files or {}) do
    staged_files_str = staged_files_str .. string.format("  %s  %s\n", file.status, file.file)
  end
  
  local extra = ""
  if opts.extra_context then
    extra = string.format("Additional context from user: %s\n", opts.extra_context)
  end
  
  local prompt = template
    :gsub("{language}", opts.language or "English")
    :gsub("{extra_context}", extra)
    :gsub("{staged_files}", staged_files_str)
    :gsub("{diff}", opts.diff or "")
  
  return prompt
end

return M
```

---

### 9. init.lua - Entry Point

**Responsibilities:**
- Setup function
- Generate function (main workflow)
- Command registration

**Implementation:**
```lua
local config = require("ai-gitcommit.config")
local git = require("ai-gitcommit.git")
local buffer = require("ai-gitcommit.buffer")
local context = require("ai-gitcommit.context")
local prompt = require("ai-gitcommit.prompt")

local M = {}

function M.setup(opts)
  config.setup(opts)
  
  -- Register command
  vim.api.nvim_create_user_command("AICommit", function(cmd_opts)
    local extra = cmd_opts.args ~= "" and cmd_opts.args or nil
    M.generate(extra)
  end, {
    nargs = "*",
    desc = "Generate commit message using AI",
  })
  
  -- Register keymap if configured
  local keymap = config.get().keymap
  if keymap then
    vim.keymap.set("n", keymap, function()
      M.generate()
    end, { desc = "AI Generate Commit Message" })
  end
end

function M.generate(extra_context)
  -- Check if in gitcommit buffer
  if not buffer.is_gitcommit_buffer() then
    vim.notify("Not in a gitcommit buffer", vim.log.levels.WARN)
    return
  end
  
  local cfg = config.get()
  local provider_config = config.get_provider()
  
  -- Get provider module
  local provider = require("ai-gitcommit.providers." .. cfg.provider)
  
  -- Show loading indicator
  vim.notify("Generating commit message...", vim.log.levels.INFO)
  
  -- Get git info
  git.get_staged_diff(function(diff)
    git.get_staged_files(function(files)
      if diff == "" then
        vim.notify("No staged changes found", vim.log.levels.WARN)
        return
      end
      
      -- Build context
      local processed_diff = context.build_context(diff, files, cfg)
      
      -- Build prompt
      local final_prompt = prompt.build({
        style = cfg.commit_style,
        language = cfg.language,
        extra_context = extra_context,
        files = files,
        diff = processed_diff,
      })
      
      -- Generate with streaming
      local message = ""
      provider.generate(
        final_prompt,
        provider_config,
        function(chunk)  -- on_chunk
          message = message .. chunk
          buffer.set_commit_message(message)
        end,
        function()  -- on_done
          vim.notify("Commit message generated!", vim.log.levels.INFO)
        end,
        function(err)  -- on_error
          vim.notify("Error: " .. err, vim.log.levels.ERROR)
        end
      )
    end)
  end)
end

return M
```

---

## OAuth Authentication Module

### Overview

The plugin supports multiple OAuth authentication methods for different providers:

| Provider | OAuth Method | Token Storage | Status |
|----------|--------------|---------------|--------|
| **GitHub Copilot** | Device Flow | `~/.config/github-copilot/` | Planned |
| **OpenAI Codex** | OAuth 2.0 | `~/.config/ai-gitcommit/` | Reserved |
| **Claude Code** | OAuth 2.0 | `~/.config/ai-gitcommit/` | Reserved |

### 1. auth/init.lua - Auth Module Entry Point

```lua
local M = {}

-- Get authentication for a provider
-- Returns token or triggers OAuth flow if needed
function M.get_token(provider_name, callback)
  local auth_module = require("ai-gitcommit.auth." .. provider_name)
  auth_module.get_token(callback)
end

-- Check if provider is authenticated
function M.is_authenticated(provider_name)
  local auth_module = require("ai-gitcommit.auth." .. provider_name)
  return auth_module.is_authenticated()
end

-- Trigger login flow for provider
function M.login(provider_name, callback)
  local auth_module = require("ai-gitcommit.auth." .. provider_name)
  auth_module.login(callback)
end

-- Logout / clear credentials
function M.logout(provider_name)
  local auth_module = require("ai-gitcommit.auth." .. provider_name)
  auth_module.logout()
end

return M
```

### 2. auth/copilot.lua - GitHub Copilot OAuth (Device Flow)

**OAuth Device Flow:**
1. Request device code from GitHub
2. User visits URL and enters code
3. Poll for access token
4. Exchange for Copilot token
5. Store and refresh tokens

**Token Storage:** `~/.config/github-copilot/hosts.json`

```lua
local M = {}

-- GitHub OAuth endpoints
local GITHUB_DEVICE_CODE_URL = "https://github.com/login/device/code"
local GITHUB_ACCESS_TOKEN_URL = "https://github.com/login/oauth/access_token"
local COPILOT_TOKEN_URL = "https://api.github.com/copilot_internal/v2/token"

-- GitHub OAuth client ID (same as VS Code Copilot)
local CLIENT_ID = "Iv1.b507a08c87ecfe98"

-- Token storage path
local function get_token_path()
  local config_dir = vim.fn.expand("~/.config/github-copilot")
  return config_dir .. "/hosts.json"
end

-- Check if authenticated
function M.is_authenticated()
  local token_path = get_token_path()
  if vim.fn.filereadable(token_path) == 0 then
    return false
  end
  
  local content = vim.fn.readfile(token_path)
  local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
  if not ok or not data["github.com"] then
    return false
  end
  
  return data["github.com"].oauth_token ~= nil
end

-- Get stored token
function M.get_token(callback)
  if not M.is_authenticated() then
    callback(nil, "Not authenticated. Run :AICommitLogin copilot")
    return
  end
  
  local token_path = get_token_path()
  local content = vim.fn.readfile(token_path)
  local data = vim.json.decode(table.concat(content, "\n"))
  local oauth_token = data["github.com"].oauth_token
  
  -- Exchange OAuth token for Copilot token
  M.get_copilot_token(oauth_token, callback)
end

-- Get Copilot API token from OAuth token
function M.get_copilot_token(oauth_token, callback)
  vim.system({
    "curl", "-s",
    "-H", "Authorization: token " .. oauth_token,
    "-H", "Accept: application/json",
    COPILOT_TOKEN_URL
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "Failed to get Copilot token")
        return
      end
      
      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok or not data.token then
        callback(nil, "Invalid Copilot token response")
        return
      end
      
      callback({
        token = data.token,
        expires_at = data.expires_at,
      })
    end)
  end)
end

-- Start OAuth Device Flow login
function M.login(callback)
  -- Step 1: Request device code
  vim.system({
    "curl", "-s",
    "-X", "POST",
    "-H", "Accept: application/json",
    "-d", "client_id=" .. CLIENT_ID .. "&scope=read:user",
    GITHUB_DEVICE_CODE_URL
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "Failed to get device code")
        return
      end
      
      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok or not data.device_code then
        callback(nil, "Invalid device code response")
        return
      end
      
      -- Show user the verification URL and code
      local msg = string.format(
        "Please visit: %s\nAnd enter code: %s",
        data.verification_uri,
        data.user_code
      )
      vim.notify(msg, vim.log.levels.INFO)
      
      -- Open browser (optional)
      if vim.fn.has("mac") == 1 then
        vim.fn.system({ "open", data.verification_uri })
      elseif vim.fn.has("unix") == 1 then
        vim.fn.system({ "xdg-open", data.verification_uri })
      end
      
      -- Step 2: Poll for access token
      M.poll_for_token(data.device_code, data.interval or 5, callback)
    end)
  end)
end

-- Poll for access token
function M.poll_for_token(device_code, interval, callback)
  local poll_count = 0
  local max_polls = 60  -- 5 minutes max
  
  local function poll()
    poll_count = poll_count + 1
    if poll_count > max_polls then
      callback(nil, "Login timed out")
      return
    end
    
    vim.system({
      "curl", "-s",
      "-X", "POST",
      "-H", "Accept: application/json",
      "-d", string.format(
        "client_id=%s&device_code=%s&grant_type=urn:ietf:params:oauth:grant-type:device_code",
        CLIENT_ID, device_code
      ),
      GITHUB_ACCESS_TOKEN_URL
    }, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          vim.defer_fn(poll, interval * 1000)
          return
        end
        
        local ok, data = pcall(vim.json.decode, result.stdout)
        if not ok then
          vim.defer_fn(poll, interval * 1000)
          return
        end
        
        if data.error == "authorization_pending" then
          vim.defer_fn(poll, interval * 1000)
          return
        end
        
        if data.error == "slow_down" then
          interval = interval + 5
          vim.defer_fn(poll, interval * 1000)
          return
        end
        
        if data.access_token then
          -- Step 3: Store token
          M.store_token(data.access_token)
          vim.notify("GitHub Copilot authenticated successfully!", vim.log.levels.INFO)
          callback({ oauth_token = data.access_token })
          return
        end
        
        if data.error then
          callback(nil, "OAuth error: " .. data.error)
          return
        end
        
        vim.defer_fn(poll, interval * 1000)
      end)
    end)
  end
  
  poll()
end

-- Store OAuth token
function M.store_token(oauth_token)
  local config_dir = vim.fn.expand("~/.config/github-copilot")
  vim.fn.mkdir(config_dir, "p")
  
  local token_path = get_token_path()
  local data = {
    ["github.com"] = {
      oauth_token = oauth_token,
    }
  }
  
  local content = vim.json.encode(data)
  vim.fn.writefile({ content }, token_path)
end

-- Logout
function M.logout()
  local token_path = get_token_path()
  if vim.fn.filereadable(token_path) == 1 then
    vim.fn.delete(token_path)
  end
  vim.notify("GitHub Copilot logged out", vim.log.levels.INFO)
end

return M
```

### 3. auth/codex.lua - OpenAI Codex OAuth (Reserved)

```lua
-- Reserved for future OpenAI Codex OAuth implementation
-- 
-- OAuth Flow (to be implemented):
-- 1. Redirect to OpenAI authorization endpoint
-- 2. User grants access
-- 3. Exchange authorization code for tokens
-- 4. Store and refresh tokens
--
-- Token Storage: ~/.config/ai-gitcommit/openai.json

local M = {}

function M.is_authenticated()
  -- TODO: Implement when OpenAI Codex OAuth is available
  return false
end

function M.get_token(callback)
  callback(nil, "OpenAI Codex OAuth not yet implemented")
end

function M.login(callback)
  callback(nil, "OpenAI Codex OAuth not yet implemented")
end

function M.logout()
  vim.notify("OpenAI Codex OAuth not yet implemented", vim.log.levels.WARN)
end

return M
```

### 4. auth/claude.lua - Claude Code OAuth (Reserved)

```lua
-- Reserved for future Claude Code OAuth implementation
--
-- Based on Claude Code CLI authentication:
-- - Uses claude /login command flow
-- - Token stored in system keychain (macOS) or secure storage
-- - Supports Claude for Teams/Enterprise SSO
--
-- Token Storage: System keychain or ~/.config/ai-gitcommit/claude.json

local M = {}

-- Claude Code OAuth endpoints (to be confirmed)
-- local CLAUDE_AUTH_URL = "https://claude.ai/oauth/authorize"
-- local CLAUDE_TOKEN_URL = "https://claude.ai/oauth/token"

function M.is_authenticated()
  -- TODO: Check for existing Claude Code credentials
  -- Could check for claude CLI authentication status
  return false
end

function M.get_token(callback)
  callback(nil, "Claude Code OAuth not yet implemented")
end

function M.login(callback)
  -- TODO: Implement Claude Code OAuth flow
  -- May integrate with claude CLI: claude /login
  callback(nil, "Claude Code OAuth not yet implemented")
end

function M.logout()
  vim.notify("Claude Code OAuth not yet implemented", vim.log.levels.WARN)
end

return M
```

### 5. providers/copilot.lua - GitHub Copilot Provider

```lua
local stream = require("ai-gitcommit.stream")
local auth = require("ai-gitcommit.auth.copilot")

local M = {}

-- Copilot API endpoint
local COPILOT_CHAT_URL = "https://api.githubcopilot.com/chat/completions"

function M.generate(prompt, config, on_chunk, on_done, on_error)
  -- Get Copilot token via OAuth
  auth.get_token(function(token_data, err)
    if err then
      on_error(err)
      return
    end
    
    local body = {
      model = config.model or "gpt-4o",
      messages = {
        { role = "user", content = prompt }
      },
      max_tokens = config.max_tokens or 500,
      temperature = 0.3,
      stream = true,
    }
    
    stream.request({
      url = COPILOT_CHAT_URL,
      method = "POST",
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. token_data.token,
        ["Editor-Version"] = "Neovim/" .. vim.version().major .. "." .. vim.version().minor,
        ["Copilot-Integration-Id"] = "vscode-chat",
      },
      body = body,
    }, function(chunk)
      -- Parse OpenAI-compatible streaming format
      local content = chunk.choices and chunk.choices[1]
        and chunk.choices[1].delta and chunk.choices[1].delta.content
      if content then
        on_chunk(content)
      end
    end, on_done, on_error)
  end)
end

return M
```

### 6. Commands for OAuth Management

```lua
-- In init.lua, add OAuth commands:

-- Login command
vim.api.nvim_create_user_command("AICommitLogin", function(opts)
  local provider = opts.args ~= "" and opts.args or config.get().provider
  local auth = require("ai-gitcommit.auth")
  
  auth.login(provider, function(result, err)
    if err then
      vim.notify("Login failed: " .. err, vim.log.levels.ERROR)
    end
  end)
end, {
  nargs = "?",
  complete = function()
    return { "copilot", "codex", "claude" }
  end,
  desc = "Login to AI provider",
})

-- Logout command
vim.api.nvim_create_user_command("AICommitLogout", function(opts)
  local provider = opts.args ~= "" and opts.args or config.get().provider
  local auth = require("ai-gitcommit.auth")
  auth.logout(provider)
end, {
  nargs = "?",
  complete = function()
    return { "copilot", "codex", "claude" }
  end,
  desc = "Logout from AI provider",
})

-- Status command
vim.api.nvim_create_user_command("AICommitStatus", function()
  local auth = require("ai-gitcommit.auth")
  local providers = { "copilot", "codex", "claude" }
  
  local lines = { "AI Commit Authentication Status:", "" }
  for _, provider in ipairs(providers) do
    local status = auth.is_authenticated(provider) and "✓ Authenticated" or "✗ Not authenticated"
    table.insert(lines, string.format("  %s: %s", provider, status))
  end
  
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, {
  desc = "Show authentication status",
})
```

---

## Development Phases

| Phase | Task | Files |
|-------|------|-------|
| **1** | Configuration management | `config.lua` |
| **2** | Git operations | `git.lua` |
| **3** | Streaming HTTP | `stream.lua` |
| **4** | OpenAI Provider | `providers/openai.lua` |
| **5** | Anthropic Provider | `providers/anthropic.lua` |
| **6** | Buffer operations | `buffer.lua` |
| **7** | Context filtering | `context.lua` |
| **8** | Prompt templates | `prompt.lua` |
| **9** | Entry point + commands | `init.lua` |
| **10** | Auto-load | `plugin/ai-gitcommit.lua` |
| **11** | **Auth module base** | `auth/init.lua` |
| **12** | **GitHub Copilot OAuth** | `auth/copilot.lua`, `providers/copilot.lua` |
| **13** | **OAuth commands** | `:AICommitLogin`, `:AICommitLogout`, `:AICommitStatus` |
| **14** | (Reserved) OpenAI Codex OAuth | `auth/codex.lua` |
| **15** | (Reserved) Claude Code OAuth | `auth/claude.lua` |

---

## Multi-language Output Examples

```
# language = "English"
feat(auth): add JWT token refresh mechanism

# language = "Chinese"
feat(auth): 添加 JWT 令牌刷新机制

# language = "Japanese"
feat(auth): JWTトークンのリフレッシュ機能を追加

# language = "Korean"
feat(auth): JWT 토큰 갱신 메커니즘 추가
```

---

## Technical Notes

### No External Dependencies

This plugin uses only:
- `vim.system()` - Neovim 0.11+ built-in async command execution
- `vim.fn.jobstart()` - For streaming support
- `vim.json.encode/decode` - Built-in JSON handling
- `curl` command - System utility (required)

### Streaming Implementation

Uses `vim.fn.jobstart()` with `stdout_buffered = false` to receive data chunks in real-time, parsing SSE (Server-Sent Events) format from LLM APIs.

### Token Estimation

Simple heuristic: `tokens ≈ characters / 4`

This is approximate but sufficient for context window management.

---

## Testing Strategy

### Testing Framework: mini.test

**Why mini.test:**
- No external dependencies (aligns with project principles)
- Built-in child Neovim process for integration testing
- Supports busted-style syntax (`describe`, `it`)
- Excellent test isolation

### Test Directory Structure

```
ai-gitcommit.nvim/
├── tests/
│   ├── helpers.lua               # Shared test utilities
│   ├── mocks/
│   │   ├── vim_system.lua        # Mock for vim.system
│   │   └── jobstart.lua          # Mock for vim.fn.jobstart
│   ├── test_config.lua           # Config module tests
│   ├── test_git.lua              # Git module tests
│   ├── test_buffer.lua           # Buffer module tests
│   ├── test_context.lua          # Context module tests
│   ├── test_prompt.lua           # Prompt module tests
│   ├── test_stream.lua           # Stream module tests
│   ├── test_providers.lua        # Provider tests
│   └── test_auth.lua             # OAuth tests
├── scripts/
│   └── minimal_init.lua          # Test initialization script
├── Makefile                      # Test commands
└── .github/
    └── workflows/
        └── ci.yml                # GitHub Actions CI
```

### Test Initialization Script

```lua
-- scripts/minimal_init.lua
vim.cmd([[let &rtp.=','.getcwd()]])

-- Add mini.nvim to runtime path for testing
vim.cmd("set rtp+=deps/mini.nvim")

-- Setup mini.test
require("mini.test").setup()

-- Consistent test environment
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
```

### Test Helpers

```lua
-- tests/helpers.lua
local Helpers = {}

-- Re-export mini.test expectations
Helpers.expect = vim.deepcopy(MiniTest.expect)
Helpers.eq = MiniTest.expect.equality
Helpers.neq = MiniTest.expect.no_equality

-- Custom expectations
Helpers.expect.match = MiniTest.new_expectation(
  "string matching",
  function(str, pattern) return str:find(pattern) ~= nil end,
  function(str, pattern)
    return string.format("Pattern: %s\nObserved string: %s", vim.inspect(pattern), str)
  end
)

-- Create child Neovim process
Helpers.new_child_neovim = function()
  local child = MiniTest.new_child_neovim()

  child.setup = function()
    child.restart({ "-u", "scripts/minimal_init.lua" })
    child.bo.readonly = false
  end

  child.set_lines = function(arr, start, finish)
    if type(arr) == "string" then arr = vim.split(arr, "\n") end
    child.api.nvim_buf_set_lines(0, start or 0, finish or -1, false, arr)
  end

  child.get_lines = function(start, finish)
    return child.api.nvim_buf_get_lines(0, start or 0, finish or -1, false)
  end

  return child
end

-- Mock vim.system for testing
Helpers.mock_vim_system = function(mock_responses)
  local orig_system = vim.system
  local call_index = 0
  
  vim.system = function(cmd, opts, callback)
    call_index = call_index + 1
    local response = mock_responses[call_index] or { code = 0, stdout = "", stderr = "" }
    
    if callback then
      vim.schedule(function()
        callback(response)
      end)
      return { wait = function() return response end }
    else
      return { wait = function() return response end }
    end
  end
  
  return function()
    vim.system = orig_system
  end
end

-- Mock vim.fn.jobstart for streaming tests
Helpers.mock_jobstart = function(mock_chunks, exit_code)
  local orig_jobstart = vim.fn.jobstart
  
  vim.fn.jobstart = function(cmd, opts)
    vim.schedule(function()
      -- Send mock chunks
      for _, chunk in ipairs(mock_chunks or {}) do
        if opts.on_stdout then
          opts.on_stdout(nil, { chunk })
        end
      end
      -- Send exit
      if opts.on_exit then
        opts.on_exit(nil, exit_code or 0)
      end
    end)
    return 1  -- job id
  end
  
  return function()
    vim.fn.jobstart = orig_jobstart
  end
end

return Helpers
```

### Test Cases by Module

#### 1. test_config.lua

```lua
-- tests/test_config.lua
local h = require("tests.helpers")
local T = MiniTest.new_set()

T["config"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ai-gitcommit.config"] = nil
    end,
  },
})

T["config"]["setup()"] = MiniTest.new_set()

T["config"]["setup()"]["merges user config with defaults"] = function()
  local config = require("ai-gitcommit.config")
  config.setup({ language = "Chinese" })
  
  local cfg = config.get()
  h.eq(cfg.language, "Chinese")
  h.eq(cfg.provider, "openai")  -- default
end

T["config"]["setup()"]["validates provider name"] = function()
  local config = require("ai-gitcommit.config")
  h.expect.error(function()
    config.setup({ provider = "invalid_provider" })
  end)
end

T["config"]["get_api_key()"] = MiniTest.new_set()

T["config"]["get_api_key()"]["returns env variable"] = function()
  vim.env.TEST_API_KEY = "test-key-123"
  local config = require("ai-gitcommit.config")
  config.setup({
    providers = {
      openai = { api_key = vim.env.TEST_API_KEY }
    }
  })
  
  local key = config.get_provider().api_key
  h.eq(key, "test-key-123")
  vim.env.TEST_API_KEY = nil
end

T["config"]["get_api_key()"]["returns function result"] = function()
  local config = require("ai-gitcommit.config")
  config.setup({
    providers = {
      openai = { api_key = function() return "func-key" end }
    }
  })
  
  local provider_cfg = config.get_provider()
  local key = type(provider_cfg.api_key) == "function" and provider_cfg.api_key() or provider_cfg.api_key
  h.eq(key, "func-key")
end

return T
```

#### 2. test_git.lua

```lua
-- tests/test_git.lua
local h = require("tests.helpers")
local T = MiniTest.new_set()

T["git"] = MiniTest.new_set()

T["git"]["get_staged_diff()"] = MiniTest.new_set()

T["git"]["get_staged_diff()"]["returns diff content"] = function()
  local restore = h.mock_vim_system({
    { code = 0, stdout = "diff --git a/file.lua b/file.lua\n+new line" }
  })
  
  local git = require("ai-gitcommit.git")
  local result = nil
  
  git.get_staged_diff(function(diff)
    result = diff
  end)
  
  vim.wait(100, function() return result ~= nil end)
  h.expect.match(result, "diff %-%-git")
  restore()
end

T["git"]["get_staged_diff()"]["returns empty string when no changes"] = function()
  local restore = h.mock_vim_system({
    { code = 0, stdout = "" }
  })
  
  local git = require("ai-gitcommit.git")
  local result = nil
  
  git.get_staged_diff(function(diff)
    result = diff
  end)
  
  vim.wait(100, function() return result ~= nil end)
  h.eq(result, "")
  restore()
end

T["git"]["get_staged_files()"] = MiniTest.new_set()

T["git"]["get_staged_files()"]["parses file status correctly"] = function()
  local restore = h.mock_vim_system({
    { code = 0, stdout = "M\tlua/test.lua\nA\tlua/new.lua\nD\tlua/deleted.lua" }
  })
  
  local git = require("ai-gitcommit.git")
  local result = nil
  
  git.get_staged_files(function(files)
    result = files
  end)
  
  vim.wait(100, function() return result ~= nil end)
  h.eq(#result, 3)
  h.eq(result[1].status, "M")
  h.eq(result[1].file, "lua/test.lua")
  h.eq(result[2].status, "A")
  h.eq(result[3].status, "D")
  restore()
end

return T
```

#### 3. test_buffer.lua

```lua
-- tests/test_buffer.lua
local h = require("tests.helpers")
local child = h.new_child_neovim()
local T = MiniTest.new_set()

T["buffer"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.lua([[buffer = require("ai-gitcommit.buffer")]])
    end,
    post_once = child.stop,
  },
})

T["buffer"]["is_gitcommit_buffer()"] = MiniTest.new_set()

T["buffer"]["is_gitcommit_buffer()"]["returns true for gitcommit filetype"] = function()
  child.cmd("set filetype=gitcommit")
  local result = child.lua([[return buffer.is_gitcommit_buffer()]])
  h.eq(result, true)
end

T["buffer"]["is_gitcommit_buffer()"]["returns false for other filetypes"] = function()
  child.cmd("set filetype=lua")
  local result = child.lua([[return buffer.is_gitcommit_buffer()]])
  h.eq(result, false)
end

T["buffer"]["find_first_comment_line()"] = MiniTest.new_set()

T["buffer"]["find_first_comment_line()"]["finds comment line"] = function()
  child.set_lines({
    "feat: add feature",
    "",
    "# Please enter the commit message",
    "# Changes to be committed:",
  })
  
  local result = child.lua([[return buffer.find_first_comment_line()]])
  h.eq(result, 3)
end

T["buffer"]["find_first_comment_line()"]["returns line count + 1 when no comments"] = function()
  child.set_lines({
    "feat: add feature",
    "",
    "Some description",
  })
  
  local result = child.lua([[return buffer.find_first_comment_line()]])
  h.eq(result, 4)
end

T["buffer"]["set_commit_message()"] = MiniTest.new_set()

T["buffer"]["set_commit_message()"]["replaces content before comments"] = function()
  child.set_lines({
    "old message",
    "",
    "# Please enter the commit message",
  })
  
  child.lua([[buffer.set_commit_message("feat: new message")]])
  
  local lines = child.get_lines()
  h.eq(lines[1], "feat: new message")
  h.eq(lines[2], "")
  h.eq(lines[3], "# Please enter the commit message")
end

T["buffer"]["set_commit_message()"]["adds empty line after message"] = function()
  child.set_lines({
    "# Comment",
  })
  
  child.lua([[buffer.set_commit_message("feat: message")]])
  
  local lines = child.get_lines()
  h.eq(lines[1], "feat: message")
  h.eq(lines[2], "")
  h.eq(lines[3], "# Comment")
end

return T
```

#### 4. test_context.lua

```lua
-- tests/test_context.lua
local h = require("tests.helpers")
local T = MiniTest.new_set()

T["context"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ai-gitcommit.context"] = nil
    end,
  },
})

T["context"]["estimate_tokens()"] = function()
  local context = require("ai-gitcommit.context")
  
  h.eq(context.estimate_tokens(""), 0)
  h.eq(context.estimate_tokens("test"), 1)  -- 4 chars = 1 token
  h.eq(context.estimate_tokens("hello world!"), 3)  -- 12 chars = 3 tokens
end

T["context"]["should_exclude_file()"] = MiniTest.new_set()

T["context"]["should_exclude_file()"]["excludes lock files"] = function()
  local context = require("ai-gitcommit.context")
  local patterns = { "%.lock$", "package%-lock%.json$" }
  
  h.eq(context.should_exclude_file("yarn.lock", patterns), true)
  h.eq(context.should_exclude_file("package-lock.json", patterns), true)
  h.eq(context.should_exclude_file("main.lua", patterns), false)
end

T["context"]["filter_diff()"] = MiniTest.new_set()

T["context"]["filter_diff()"]["removes excluded files from diff"] = function()
  local context = require("ai-gitcommit.context")
  local diff = [[
diff --git a/src/main.lua b/src/main.lua
+new code
diff --git a/yarn.lock b/yarn.lock
+lock content
diff --git a/src/util.lua b/src/util.lua
+util code
]]
  
  local config = {
    filter = {
      exclude_patterns = { "%.lock$" }
    }
  }
  
  local filtered = context.filter_diff(diff, config)
  h.expect.match(filtered, "main%.lua")
  h.expect.match(filtered, "util%.lua")
  h.expect.no_match(filtered, "yarn%.lock")
end

T["context"]["truncate_diff()"] = MiniTest.new_set()

T["context"]["truncate_diff()"]["truncates long diff"] = function()
  local context = require("ai-gitcommit.context")
  local long_diff = string.rep("a", 1000)
  
  local truncated = context.truncate_diff(long_diff, 100)
  h.eq(#truncated < #long_diff, true)
  h.expect.match(truncated, "truncated")
end

T["context"]["truncate_diff()"]["keeps short diff unchanged"] = function()
  local context = require("ai-gitcommit.context")
  local short_diff = "short diff content"
  
  local result = context.truncate_diff(short_diff, 1000)
  h.eq(result, short_diff)
end

return T
```

#### 5. test_prompt.lua

```lua
-- tests/test_prompt.lua
local h = require("tests.helpers")
local T = MiniTest.new_set()

T["prompt"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ai-gitcommit.prompt"] = nil
    end,
  },
})

T["prompt"]["build()"] = MiniTest.new_set()

T["prompt"]["build()"]["includes language in prompt"] = function()
  local prompt = require("ai-gitcommit.prompt")
  
  local result = prompt.build({
    style = "conventional",
    language = "Chinese",
    diff = "test diff",
    files = {},
  })
  
  h.expect.match(result, "Chinese")
end

T["prompt"]["build()"]["includes extra context when provided"] = function()
  local prompt = require("ai-gitcommit.prompt")
  
  local result = prompt.build({
    style = "conventional",
    language = "English",
    extra_context = "Fix the login bug",
    diff = "test diff",
    files = {},
  })
  
  h.expect.match(result, "Fix the login bug")
end

T["prompt"]["build()"]["includes staged files"] = function()
  local prompt = require("ai-gitcommit.prompt")
  
  local result = prompt.build({
    style = "conventional",
    language = "English",
    diff = "test diff",
    files = {
      { status = "M", file = "src/main.lua" },
      { status = "A", file = "src/new.lua" },
    },
  })
  
  h.expect.match(result, "M%s+src/main%.lua")
  h.expect.match(result, "A%s+src/new%.lua")
end

T["prompt"]["build()"]["uses correct template for style"] = function()
  local prompt = require("ai-gitcommit.prompt")
  
  local conventional = prompt.build({
    style = "conventional",
    language = "English",
    diff = "test",
    files = {},
  })
  
  local simple = prompt.build({
    style = "simple",
    language = "English",
    diff = "test",
    files = {},
  })
  
  h.expect.match(conventional, "Conventional Commits")
  h.expect.no_match(simple, "Conventional Commits")
end

return T
```

#### 6. test_providers.lua

```lua
-- tests/test_providers.lua
local h = require("tests.helpers")
local T = MiniTest.new_set()

T["providers"] = MiniTest.new_set()

T["providers"]["openai"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ai-gitcommit.providers.openai"] = nil
      package.loaded["ai-gitcommit.stream"] = nil
    end,
  },
})

T["providers"]["openai"]["generate() calls stream.request with correct params"] = function()
  -- Mock stream module
  local called_opts = nil
  package.loaded["ai-gitcommit.stream"] = {
    request = function(opts, on_chunk, on_done, on_error)
      called_opts = opts
      on_done()
    end
  }
  
  local openai = require("ai-gitcommit.providers.openai")
  local done = false
  
  openai.generate(
    "test prompt",
    {
      model = "gpt-4o-mini",
      endpoint = "https://api.openai.com/v1/chat/completions",
      api_key = "test-key",
      max_tokens = 500,
    },
    function() end,
    function() done = true end,
    function() end
  )
  
  vim.wait(100, function() return done end)
  
  h.eq(called_opts.url, "https://api.openai.com/v1/chat/completions")
  h.eq(called_opts.method, "POST")
  h.expect.match(called_opts.headers["Authorization"], "Bearer test%-key")
  h.eq(called_opts.body.model, "gpt-4o-mini")
  h.eq(called_opts.body.stream, true)
end

T["providers"]["anthropic"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ai-gitcommit.providers.anthropic"] = nil
      package.loaded["ai-gitcommit.stream"] = nil
    end,
  },
})

T["providers"]["anthropic"]["generate() uses correct headers"] = function()
  local called_opts = nil
  package.loaded["ai-gitcommit.stream"] = {
    request = function(opts, on_chunk, on_done, on_error)
      called_opts = opts
      on_done()
    end
  }
  
  local anthropic = require("ai-gitcommit.providers.anthropic")
  local done = false
  
  anthropic.generate(
    "test prompt",
    {
      model = "claude-3-5-sonnet-20241022",
      endpoint = "https://api.anthropic.com/v1/messages",
      api_key = "test-key",
      max_tokens = 500,
    },
    function() end,
    function() done = true end,
    function() end
  )
  
  vim.wait(100, function() return done end)
  
  h.eq(called_opts.headers["x-api-key"], "test-key")
  h.eq(called_opts.headers["anthropic-version"], "2023-06-01")
end

return T
```

#### 7. test_auth.lua

```lua
-- tests/test_auth.lua
local h = require("tests.helpers")
local T = MiniTest.new_set()

T["auth"] = MiniTest.new_set()

T["auth"]["copilot"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ai-gitcommit.auth.copilot"] = nil
    end,
  },
})

T["auth"]["copilot"]["is_authenticated() returns false when no token file"] = function()
  local restore = h.mock_vim_fn({
    filereadable = function() return 0 end,
  })
  
  local copilot = require("ai-gitcommit.auth.copilot")
  h.eq(copilot.is_authenticated(), false)
  restore()
end

T["auth"]["copilot"]["is_authenticated() returns true when valid token exists"] = function()
  local token_data = vim.json.encode({
    ["github.com"] = { oauth_token = "test-token" }
  })
  
  local restore = h.mock_vim_fn({
    filereadable = function() return 1 end,
    readfile = function() return { token_data } end,
  })
  
  local copilot = require("ai-gitcommit.auth.copilot")
  h.eq(copilot.is_authenticated(), true)
  restore()
end

T["auth"]["copilot"]["get_copilot_token() exchanges oauth for copilot token"] = function()
  local restore = h.mock_vim_system({
    { 
      code = 0, 
      stdout = vim.json.encode({
        token = "copilot-token-123",
        expires_at = 9999999999,
      })
    }
  })
  
  local copilot = require("ai-gitcommit.auth.copilot")
  local result = nil
  
  copilot.get_copilot_token("oauth-token", function(data, err)
    result = { data = data, err = err }
  end)
  
  vim.wait(100, function() return result ~= nil end)
  h.eq(result.err, nil)
  h.eq(result.data.token, "copilot-token-123")
  restore()
end

T["auth"]["copilot"]["store_token() creates config directory and saves token"] = function()
  local created_dir = nil
  local written_file = nil
  local written_content = nil
  
  local restore = h.mock_vim_fn({
    expand = function(path) return "/home/user/.config/github-copilot" end,
    mkdir = function(dir) created_dir = dir end,
    writefile = function(content, path)
      written_content = content
      written_file = path
    end,
  })
  
  local copilot = require("ai-gitcommit.auth.copilot")
  copilot.store_token("test-oauth-token")
  
  h.expect.match(created_dir, "github%-copilot")
  h.expect.match(written_file, "hosts%.json")
  h.expect.match(written_content[1], "test%-oauth%-token")
  restore()
end

T["auth"]["codex"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ai-gitcommit.auth.codex"] = nil
    end,
  },
})

T["auth"]["codex"]["is_authenticated() returns false (not implemented)"] = function()
  local codex = require("ai-gitcommit.auth.codex")
  h.eq(codex.is_authenticated(), false)
end

T["auth"]["claude"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ai-gitcommit.auth.claude"] = nil
    end,
  },
})

T["auth"]["claude"]["is_authenticated() returns false (not implemented)"] = function()
  local claude = require("ai-gitcommit.auth.claude")
  h.eq(claude.is_authenticated(), false)
end

return T
```

### Makefile

```makefile
# Makefile

.PHONY: all test test_file deps clean

all: test

# Run all tests
test: deps
	@echo "Running tests..."
	nvim --headless --noplugin -u ./scripts/minimal_init.lua \
		-c "lua MiniTest.run()"

# Run single test file: make test_file FILE=tests/test_config.lua
test_file: deps
	@echo "Running $(FILE)..."
	nvim --headless --noplugin -u ./scripts/minimal_init.lua \
		-c "lua MiniTest.run_file('$(FILE)')"

# Install test dependencies
deps: deps/mini.nvim

deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none --depth 1 https://github.com/echasnovski/mini.nvim $@

# Clean dependencies
clean:
	rm -rf deps
```

### GitHub Actions CI

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    name: Test on Neovim ${{ matrix.nvim_version }}
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        nvim_version: ['v0.11.0', 'nightly']

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Neovim
        uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: ${{ matrix.nvim_version }}

      - name: Run tests
        run: make test

  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Check formatting with StyLua
        uses: JohnnyMorganz/stylua-action@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          version: latest
          args: --check lua/ tests/
```

### Running Tests

```bash
# Run all tests
make test

# Run single test file
make test_file FILE=tests/test_config.lua

# Run tests with verbose output
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run({ execute = { reporter = MiniTest.gen_reporter.stdout({ group_depth = 2 }) } })"
```

---

## Updated Development Phases

| Phase | Task | Files |
|-------|------|-------|
| **1** | Configuration management | `config.lua` |
| **2** | Git operations | `git.lua` |
| **3** | Streaming HTTP | `stream.lua` |
| **4** | OpenAI Provider | `providers/openai.lua` |
| **5** | Anthropic Provider | `providers/anthropic.lua` |
| **6** | Buffer operations | `buffer.lua` |
| **7** | Context filtering | `context.lua` |
| **8** | Prompt templates | `prompt.lua` |
| **9** | Entry point + commands | `init.lua` |
| **10** | Auto-load | `plugin/ai-gitcommit.lua` |
| **11** | **Auth module base** | `auth/init.lua` |
| **12** | **GitHub Copilot OAuth** | `auth/copilot.lua`, `providers/copilot.lua` |
| **13** | **OAuth commands** | `:AICommitLogin`, `:AICommitLogout`, `:AICommitStatus` |
| **14** | Test setup + helpers | `scripts/minimal_init.lua`, `tests/helpers.lua` |
| **15** | Unit tests (including OAuth) | `tests/test_*.lua` |
| **16** | CI setup | `.github/workflows/ci.yml`, `Makefile` |
| **17** | Documentation | `doc/ai-gitcommit.txt`, `README.md` |
| **18** | (Reserved) OpenAI Codex OAuth | `auth/codex.lua` |
| **19** | (Reserved) Claude Code OAuth | `auth/claude.lua` |
