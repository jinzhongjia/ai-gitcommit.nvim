# ai-gitcommit.nvim

AI 驱动的 Neovim git commit 信息生成器。

## 依赖

- Neovim 0.11+
- curl
- API key (OpenAI/Anthropic) 或 GitHub Copilot

## 安装

```lua
-- lazy.nvim
{
  "your-username/ai-gitcommit.nvim",
  event = "FileType gitcommit",
  opts = {
    provider = "openai", -- "openai" | "anthropic" | "copilot"
    language = "Chinese", -- 中文 commit message
  },
}
```

## 使用

```vim
:AICommit                       " 生成 commit message
:AICommit [附加说明]             " 带上下文生成
:AICommit login copilot         " OAuth 登录
:AICommit logout copilot        " OAuth 登出
:AICommit status                " 查看认证状态
```

## 配置

```lua
require("ai-gitcommit").setup({
  model = "claude-haiku-4-5",
  endpoint = "https://api.anthropic.com/v1/messages",
  max_tokens = 500,
  languages = { "Chinese", "English" }, -- 支持的语言
  prompt_template = nil, -- 自定义 prompt 模板（可选）
  keymap = nil, -- 如 "<leader>gc"
  context = {
    max_diff_lines = 500,
    max_diff_chars = 15000,
  },
  filter = {
    exclude_patterns = { "%.lock$", "package%-lock%.json$" },
    exclude_paths = {},
  },
})
```

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
