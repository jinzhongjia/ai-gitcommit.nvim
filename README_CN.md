# ai-gitcommit.nvim

AI 驱动的 Neovim git commit 信息生成器。

## 依赖

- Neovim 0.11+
- curl
- API key（OpenAI/Anthropic）或 GitHub Copilot（OAuth）

## 安装

```lua
-- lazy.nvim
{
  "your-username/ai-gitcommit.nvim",
  event = "FileType gitcommit",
  opts = {
    provider = "openai", -- 必填: "openai" | "anthropic" | "copilot"
    providers = {
      openai = {
        api_key = vim.env.OPENAI_API_KEY,
      },
    },
    languages = { "Chinese", "English" },
  },
}
```

## 迁移说明

旧版平铺配置已不再支持。必须配置：
- `provider`
- `providers.<name>`

如果未设置 `provider`，`:AICommit` 会直接报配置错误。

## 使用

```vim
:AICommit                       " 生成 commit message
:AICommit [附加说明]             " 带上下文生成
:AICommit login <provider>      " OAuth 登录（anthropic/copilot）
:AICommit logout <provider>     " 退出登录
:AICommit status                " 查看全部 provider 状态
:AICommit status <provider>     " 查看单个 provider 状态
```

## 配置

```lua
require("ai-gitcommit").setup({
  provider = "openai", -- 必填

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
      model = "gpt-4o",
      endpoint = "https://api.githubcopilot.com/chat/completions",
      max_tokens = 500,
      client_id = nil, -- 可选，nil 表示使用内置默认值
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

Provider 配置校验：
- `providers.<name>.model` 必须是非空字符串
- `providers.<name>.endpoint` 必须是非空字符串
- `providers.<name>.max_tokens` 必须大于 0

OpenAI 兼容接口：
- 继续使用 `openai` provider，只需改 `providers.openai.endpoint`
- 无鉴权本地服务可设置 `api_key_required = false`
- 非 Bearer 鉴权可配置 `api_key_header` 和 `api_key_prefix`
- 额外请求头通过 `extra_headers` 传入
- 若服务不支持 OpenAI `stream_options`，可设置 `stream_options = false`

## Copilot OAuth

首次使用 Copilot 需要登录：

```vim
:AICommit login copilot
```

OAuth 数据存储路径：
- Linux/macOS: `stdpath("data")/ai-gitcommit/copilot.json`
- Windows: 对应 `stdpath("data")` 目录

### 自定义 Prompt 模板

```lua
require("ai-gitcommit").setup({
  prompt_template = [[
为以下更改生成 commit message。
使用 {language} 语言，简洁明了。

{extra_context}

文件: {staged_files}

Diff:
{diff}

只输出 commit message，不要解释。
]]
})
```

详细配置见 `:help ai-gitcommit`。

## License

MIT
