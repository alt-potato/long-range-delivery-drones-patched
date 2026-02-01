local util = require("util")
local item_sounds = require("__base__.prototypes.item_sounds")
local base_path = require("lib.global").consts.BASE_PATH

local depot = {
	type = "logistic-container",
	name = "long-range-delivery-drone-depot",
	localised_name = { "long-range-delivery-drone-depot" },
	localised_description = { "long-range-delivery-drone-depot-description" },
	icon = base_path .. "/graphics/icons/depot-icon.png",
	icon_size = 64,
	flags = { "placeable-player", "player-creation" },
	minable = { mining_time = 1, result = "long-range-delivery-drone-depot" },
	max_health = 500,
	collision_box = { { -2.85, -2.85 }, { 2.85, 2.85 } },
	selection_box = { { -3, -3 }, { 3, 3 } },
	render_not_in_network_icon = false,
	landing_location_offset = { 0, 2.5 },
	icon_draw_specification = {
		scale = 2,
		scale_for_many = 2,
	},
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
	inventory_size = 19,
	logistic_mode = "requester",
	open_sound = { filename = "__base__/sound/metallic-chest-open.ogg", volume = 0.43 },
	close_sound = { filename = "__base__/sound/metallic-chest-close.ogg", volume = 0.43 },
	opened_duration = 10,
	animation = {
		layers = {
			{
				filename = base_path .. "/graphics/entity/depot.png",
				width = 224,
				height = 224,
				frame_count = 1,
				shift = util.by_pixel(0, -2),
				scale = 1,
			},
			{
				filename = "__base__/graphics/entity/artillery-turret/artillery-turret-base-shadow.png",
				priority = "high",
				line_length = 1,
				width = 277,
				height = 149,
				frame_count = 1,
				shift = util.by_pixel(36, 12),
				draw_as_shadow = true,
				scale = 1,
			},
		},
	},
	circuit_wire_connection_point = circuit_connector_definitions.create_vector(universal_connector_template, {
		{
			variation = 26,
			main_offset = util.by_pixel(3, 64 + 5.5),
			shadow_offset = util.by_pixel(7.5, 64 + 7.5),
			show_shadow = true,
		},
	}).points,
	circuit_connector_sprites = circuit_connector_definitions.create_vector(universal_connector_template, {
		{
			variation = 26,
			main_offset = util.by_pixel(3, 64 + 5.5),
			shadow_offset = util.by_pixel(7.5, 64 + 7.5),
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
				effect_id = "long-range-delivery-drone-depot-created",
			},
		},
	},
}

local depot_item = {
	type = "item",
	name = "long-range-delivery-drone-depot",
	icon = depot.icon,
	icon_size = depot.icon_size,
	icon_mipmaps = depot.icon_mipmaps,
	flags = {},
	subgroup = "logistic-network",
	order = "k[long-range-delivery-drone-depot]-a",
	inventory_move_sound = item_sounds.metal_chest_inventory_move,
	pick_sound = item_sounds.metal_chest_inventory_pickup,
	drop_sound = item_sounds.metal_chest_inventory_move,
	place_result = "long-range-delivery-drone-depot",
	stack_size = 10,
}

local depot_recipe = {
	type = "recipe",
	name = "long-range-delivery-drone-depot",
	enabled = false,
	ingredients = {
		{ type = "item", name = "steel-chest", amount = 20 },
		{ type = "item", name = "electronic-circuit", amount = 15 },
		{ type = "item", name = "iron-gear-wheel", amount = 10 },
	},
	energy_required = 5,
	results = { { type = "item", name = "long-range-delivery-drone-depot", amount = 1 } },
}

data:extend({ depot, depot_item, depot_recipe })
