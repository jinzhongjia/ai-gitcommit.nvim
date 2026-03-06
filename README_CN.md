# ai-gitcommit.nvim

AI 驱动的 Neovim git commit 信息生成器。

支持的 Provider：
- OpenAI（及兼容接口）
- Anthropic
- GitHub Copilot

## 依赖

- Neovim 0.11+
- curl
- API key（OpenAI/Anthropic）或 [copilot.vim](https://github.com/github/copilot.vim) / [copilot.lua](https://github.com/zbirenbaum/copilot.lua)

## 安装

```lua
-- lazy.nvim (Copilot)
{
  "your-username/ai-gitcommit.nvim",
  event = "FileType gitcommit",
  opts = {
    provider = "copilot",
  },
}

-- lazy.nvim (OpenAI)
{
  "your-username/ai-gitcommit.nvim",
  event = "FileType gitcommit",
  opts = {
    provider = "openai",
    providers = {
      openai = {
        api_key = vim.env.OPENAI_API_KEY,
      },
    },
    languages = { "Chinese", "English" },
  },
}
```

## 使用

```vim
:AICommit                       " 生成 commit message
:AICommit [附加说明]             " 带上下文生成
:AICommit login <provider>      " OAuth 登录（仅 anthropic）
:AICommit logout <provider>     " 清除认证状态
:AICommit status                " 查看全部 provider 状态
:AICommit status <provider>     " 查看单个 provider 状态
```

## 配置

```lua
require("ai-gitcommit").setup({
  provider = "copilot", -- 必填: "openai" | "anthropic" | "copilot"

  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
      api_key_required = true,
      api_key_header = "Authorization",
      api_key_prefix = "Bearer ",
      extra_headers = {},
      stream_options = true,
      model = "gpt-4o-mini",
      endpoint = "https://api.openai.com/v1/chat/completions",
      max_tokens = 500,
    },

    anthropic = {
      api_key = vim.env.ANTHROPIC_API_KEY,
      model = "claude-haiku-4-5",
      endpoint = "https://api.anthropic.com/v1/messages",
      max_tokens = 500,
    },

    copilot = {
      model = "grok-code-fast-1",
      endpoint = "https://api.githubcopilot.com/chat/completions",
      max_tokens = 500,
    },
  },

  languages = { "Chinese", "English" },
  prompt_template = nil,
  keymap = nil,
  context = {
    max_diff_lines = 500,
    max_diff_chars = 15000,
  },
  filter = {
    exclude_patterns = { "%.lock$", "package%-lock%.json$" },
    exclude_paths = {},
    include_only = nil,
  },
  auto = {
    enabled = true,
    debounce_ms = 450,
  },
})
```

## Copilot

Copilot provider 直接读取已安装的 Copilot 插件的 OAuth token —— **无需单独登录**。

### 前提条件

安装并认证以下插件之一：
- [copilot.vim](https://github.com/github/copilot.vim) — 运行 `:Copilot auth`
- [copilot.lua](https://github.com/zbirenbaum/copilot.lua)

认证完成后，`ai-gitcommit.nvim` 会自动检测 token。

### 可用模型

具体可用模型取决于你的 Copilot 订阅级别（Free/Pro/Pro+/Business/Enterprise）：

| 模型 | ID | 备注 |
|---|---|---|
| Grok Code Fast 1 | `grok-code-fast-1` | 默认，快速经济 |
| GPT-4.1 | `gpt-4.1` | Copilot 官方默认 |
| GPT-4o | `gpt-4o` | |
| Claude Sonnet 4 | `claude-sonnet-4` | |
| o3-mini | `o3-mini` | 推理模型 |
| o4-mini | `o4-mini` | 推理模型 |

通过配置切换模型：

```lua
providers = {
  copilot = {
    model = "claude-sonnet-4",
  },
},
```

## OpenAI 兼容接口

使用 `openai` provider 配合自定义 endpoint：

```lua
providers = {
  openai = {
    endpoint = "http://localhost:11434/v1/chat/completions",
    api_key_required = false, -- 本地服务无需鉴权
    model = "llama3",
  },
},
```

- 非 Bearer 鉴权：配置 `api_key_header` 和 `api_key_prefix`
- 额外请求头：使用 `extra_headers`
- 若服务不支持 OpenAI `stream_options`：设置 `stream_options = false`

## Anthropic

```lua
{
  provider = "anthropic",
  providers = {
    anthropic = {
      api_key = vim.env.ANTHROPIC_API_KEY,
    },
  },
}
```

或使用 OAuth 登录：

```vim
:AICommit login anthropic
```

## 自定义 Prompt 模板

占位符：`{language}`、`{extra_context}`、`{staged_files}`、`{diff}`

```lua
prompt_template = [[
为以下更改生成 commit message。
使用 {language} 语言，简洁明了。

{extra_context}

文件: {staged_files}

Diff:
{diff}

只输出 commit message，不要解释。
]]
```

## Diff 上下文行为

- `filter.exclude_patterns` — 按文件名模式排除文件
- `filter.exclude_paths` — 按路径模式排除文件
- `filter.include_only` — 非空时仅保留匹配的文件
- 上下文先按 `context.max_diff_lines` 截断，再按 `context.max_diff_chars` 截断

## License

MIT
