return {
	{
		"folke/snacks.nvim",
		priority = 1000,
		opts = {
			picker = {
				enabled = true,
				sources = {
					explorer = {
						hidden = true,
						ignored = true,
					},
				},
			},
			explorer = {
				enabled = true,
			},
			animate = {
				enabled = true,
			},
			notifier = {
				enabled = true,
			},
			lazygit = {
				enabled = true,
				configure = true,
			},
			gitbrowse = {
				enabled = true,
			},
			rename = {
				enabled = true,
			},
			statuscolumn = {
				enabled = true,
			},
		},
		keys = {
			{
				"<leader>e",
				function()
					local explorer = require("snacks").picker.get({ source = "explorer" })[1]
					if explorer then
						explorer:focus()
					else
						require("snacks").explorer()
					end
				end,
				desc = "Focus or Open File Explorer",
			},
			{
				"fl",
				mode = "n",
				function()
					require("snacks").explorer()
				end,
				desc = "Open or Close File Explorer",
			},
			{
				"<leader>gg",
				function()
					require("snacks").lazygit()
				end,
				desc = "Open Lazygit",
			},
		},
	},
}
