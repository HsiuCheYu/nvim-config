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
						-- linkedProjects = { "/home/yuwhisper/projects/linux/build/rust-project.json" },
					},
				},
				tools = {
					hover_actions = { auto_focus = true },
				},
			},
		},
		config = function(_, opts)
			local state_file = vim.fn.stdpath("data") .. "/rust_target"
			local saved = vim.fn.filereadable(state_file) == 1 and vim.fn.readfile(state_file)[1] or vim.env.RA_TARGET

			if saved then
				opts.server.settings["rust-analyzer"].cargo.target = saved
			end

			vim.g.rustaceanvim = opts

			local targets = {
				linux = "x86_64-unknown-linux-gnu",
				windows = "x86_64-pc-windows-msvc",
				mac = "aarch64-apple-darwin",
				wasm = "wasm32-unknown-unknown",
			}

			vim.api.nvim_create_user_command("RustTarget", function(args)
				local target = targets[args.args] or args.args
				vim.fn.writefile({ target }, state_file)
				vim.g.rustaceanvim = vim.tbl_deep_extend("force", vim.g.rustaceanvim, {
					server = {
						settings = {
							["rust-analyzer"] = {
								cargo = { target = target },
							},
						},
					},
				})
				vim.cmd("LspRestart")
				vim.notify("rust-analyzer target → " .. target, vim.log.levels.INFO)
			end, {
				nargs = 1,
				complete = function()
					return vim.tbl_keys(targets)
				end,
			})
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
