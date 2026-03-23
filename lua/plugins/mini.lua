return {
	{
		"echasnovski/mini.nvim",
		version = false,
		config = function()
			require("mini.basics").setup()
			require("mini.comment").setup()
			require("mini.snippets").setup()
			require("mini.icons").setup()
			require("mini.statusline").setup()
			require("mini.extra").setup()
		end,
	},
}
