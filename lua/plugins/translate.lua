return {
	{
		"askfiy/smart-translate.nvim",
		cmd = { "Translate" },
		dependencies = {
			"askfiy/http.nvim",
		},
		opts = {
			default = {
				cmds = {
					source = "auto",
					target = "zh-TW",
				},
			},
		},
		keys = {
			{
				"T",
				"<cmd>Translate<cr>",
				mode = "v",
				desc = "Translate selected text",
			},
		},
	},
}
