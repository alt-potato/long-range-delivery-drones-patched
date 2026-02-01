local base_path = require("util.meta").base_path

local technology = {
	type = "technology",
	name = "long-range-delivery-drone",
	localised_name = { "long-range-delivery-drone" },
	localised_description = { "long-range-delivery-drone-description" },
	icon = base_path .. "/graphics/technology/tech-icon.png",
	icon_size = 128,
	effects = {
		{
			type = "unlock-recipe",
			recipe = "long-range-delivery-drone",
		},
		{
			type = "unlock-recipe",
			recipe = "long-range-delivery-drone-depot",
		},
		{
			type = "unlock-recipe",
			recipe = "long-range-delivery-drone-request-depot",
		},
	},
	prerequisites = { "oil-processing" },
	unit = {
		count = 500,
		ingredients = {
			{ "automation-science-pack", 1 },
			{ "logistic-science-pack", 1 },
		},
		time = 30,
	},
	order = "a-d-b",
}

data:extend({ technology })
