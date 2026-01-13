vim.cmd([[set runtimepath+=.]])
vim.cmd([[set runtimepath+=./deps/mini.nvim]])

vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false

require("mini.test").setup()
