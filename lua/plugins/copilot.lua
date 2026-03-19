return {
	{
		"zbirenbaum/copilot.lua",
		event = "InsertEnter",
		opts = {
			suggestion = {
				auto_trigger = true,
				hide_during_completion = false,
        keymap = {
          accept = "<Tab>",
        },
			},
			panel = { enabled = false },
		},
	},
}
