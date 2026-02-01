local item_sounds = require("__base__.prototypes.item_sounds")
local base_path = require("lib.meta").base_path

local request_depot = {
	type = "logistic-container",
	name = "long-range-delivery-drone-request-depot",
	localised_name = { "long-range-delivery-drone-request-depot" },
	localised_description = { "long-range-delivery-drone-request-depot-description" },
	icon = base_path .. "/graphics/icons/request-depot-icon.png",
	icon_size = 64,
	flags = { "placeable-player", "player-creation" },
	minable = { mining_time = 1, result = "long-range-delivery-drone-request-depot" },
	max_health = 350,
	corpse = "buffer-chest-remnants",
	dying_explosion = "buffer-chest-explosion",
	collision_box = { { -0.85, -0.85 }, { 0.85, 0.85 } },
	selection_box = { { -1, -1 }, { 1, 1 } },
	render_not_in_network_icon = false,
	use_exact_mode = true,
	inventory_type = "with_filters_and_bar",
	resistances = {
		{
			type = "fire",
			percent = 90,
		},
		{
			type = "impact",
			percent = 60,
		},
	},
	fast_replaceable_group = "container",
	inventory_size = 69,
	logistic_mode = "buffer",
	open_sound = { filename = "__base__/sound/metallic-chest-open.ogg", volume = 0.43 },
	close_sound = { filename = "__base__/sound/metallic-chest-close.ogg", volume = 0.43 },
	opened_duration = 10,
	animation = {
		layers = {
			{
				filename = base_path .. "/graphics/entity/request-depot.png",
				priority = "extra-high",
				width = 128,
				height = 196,
				frame_count = 1,
				shift = util.by_pixel(0, -20),
				scale = 0.5,
			},
			{
				filename = base_path .. "/graphics/entity/request-depot-shadow.png",
				priority = "extra-high",
				width = 173,
				height = 76,
				repeat_count = 1,
				shift = util.by_pixel(14, 12),
				draw_as_shadow = true,
				scale = 0.5,
			},
		},
	},
	circuit_wire_connection_point = circuit_connector_definitions.create_vector(universal_connector_template, {
		{
			variation = 26,
			main_offset = util.by_pixel(3, 16 + 5.5),
			shadow_offset = util.by_pixel(7.5, 16 + 7.5),
			show_shadow = true,
		},
	}).points,
	circuit_connector_sprites = circuit_connector_definitions.create_vector(universal_connector_template, {
		{
			variation = 26,
			main_offset = util.by_pixel(3, 16 + 5.5),
			shadow_offset = util.by_pixel(7.5, 16 + 7.5),
			show_shadow = true,
		},
	}).sprites,
	circuit_wire_max_distance = 10,
	created_effect = {
		type = "direct",
		action_delivery = {
			type = "instant",
			source_effects = {
				type = "script",
				effect_id = "long-range-delivery-drone-request-depot-created",
			},
		},
	},
}

local request_depot_item = {
	type = "item",
	name = "long-range-delivery-drone-request-depot",
	icon = request_depot.icon,
	icon_size = request_depot.icon_size,
	icon_mipmaps = request_depot.icon_mipmaps,
	flags = {},
	subgroup = "logistic-network",
	order = "k[long-range-delivery-drone-request-depot]-b",
	inventory_move_sound = item_sounds.metal_chest_inventory_move,
	pick_sound = item_sounds.metal_chest_inventory_pickup,
	drop_sound = item_sounds.metal_chest_inventory_move,
	place_result = "long-range-delivery-drone-request-depot",
	stack_size = 10,
}

local request_depot_recipe = {
	type = "recipe",
	name = "long-range-delivery-drone-request-depot",
	enabled = false,
	ingredients = {
		{ type = "item", name = "steel-chest", amount = 1 },
		{ type = "item", name = "electronic-circuit", amount = 5 },
	},
	results = { { type = "item", name = "long-range-delivery-drone-request-depot", amount = 1 } },
}

data:extend({ request_depot, request_depot_item, request_depot_recipe })
