return {
	{
		"nvim-telescope/telescope.nvim",
		version = "*",
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				-- Windows 通常沒有 make/gcc,官方建議改用 cmake (搭配 MSVC Build Tools)
				build = vim.fn.has("win32") == 1
						and "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release --target install"
					or "make",
			},
		},
		config = function()
			local telescope = require("telescope")
			telescope.setup({})
			-- fzf-native 編譯失敗時 (例如沒有 make/cmake) 退回內建排序,不報錯
			pcall(telescope.load_extension, "fzf")
		end,
		keys = {
			{ "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
			{ "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live Grep" },
			{ "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
			{ "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help Tags" },
		},
	},
}
