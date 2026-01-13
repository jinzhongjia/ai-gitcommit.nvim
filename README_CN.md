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
  provider = "openai",
  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
      model = "gpt-4o-mini",
    },
    anthropic = {
      api_key = vim.env.ANTHROPIC_API_KEY,
      model = "claude-3-5-sonnet-20241022",
    },
    copilot = {
      model = "gpt-4o",
    },
  },
  language = "Chinese", -- 输出语言
  commit_style = "conventional", -- "conventional" | "simple"
  keymap = nil, -- 如 "<leader>gc"
})
```

详细配置见 `:help ai-gitcommit`。

## License

MIT
