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
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
  vim.g.clipboard = {
    name = 'OSC 52',
    copy = {
      ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
      ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
    },
    paste = {
      ['+'] = function() return vim.fn.split(vim.fn.getreg('"'), '\n') end,
      ['*'] = function() return vim.fn.split(vim.fn.getreg('"'), '\n') end,
    },
  }
end

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
