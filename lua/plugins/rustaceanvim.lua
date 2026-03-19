return {
	{
		"mrcjkb/rustaceanvim",
		version = "^8",
		lazy = false,
		opts = {
			server = {
				settings = {
					["rust-analyzer"] = {
						check = { command = "clippy" },
						cargo = { features = "all" },
						imports = {
							granularity = { enforce = true },
							prefix = "crate",
						},
					},
				},
				tools = {
					hover_actions = { auto_focus = true },
				},
			},
		},
		config = function(_, opts)
			vim.g.rustaceanvim = opts
		end,
	},
	{
		"saecki/crates.nvim",
		ft = { "rust", "toml" },
		opts = {
			popup = { border = "rounded" },
		},
	},
}
