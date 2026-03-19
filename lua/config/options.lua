vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.termguicolors = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false

opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

opt.mouse = "a"
opt.clipboard = "unnamedplus"

opt.swapfile = false
opt.backup = false
opt.undofile = true

opt.showmode = false
opt.updatetime = 100
opt.timeoutlen = 300

opt.splitright = true
opt.splitbelow = true

opt.cmdheight = 1
opt.pumheight = 10
