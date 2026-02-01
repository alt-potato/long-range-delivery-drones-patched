local consts = require("lib.global").consts
local script_data = require("lib.global").data

local lib = {}

--#region MATH

---@class vector2
---@field x number
---@field y number

lib.tau = 2 * math.pi

lib.logistic_curve = function(x)
	local a = (x / (1 - x)) ^ 2
	return 1 - (1 / (1 + a))
end

---@param a vector2
---@param b vector2
---@return number
lib.distance_squared = function(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	return dx * dx + dy * dy
end

---@param orientation number -- Factorio orientation value [0, 1)
---@return number radians -- orientation converted to radians
lib.to_rad = function(orientation)
	local adjusted_orientation = orientation - 0.25
	if adjusted_orientation < 0 then
		adjusted_orientation = adjusted_orientation + 1
	end
	return adjusted_orientation * lib.tau
end

lib.safe_number = function(value)
	return type(value) == "number" and value or 0
end

--#endregion

--#region ITEM

local stack_sizes_cache = {}
lib.get_stack_size = function(item_name)
	local stack_size = stack_sizes_cache[item_name]
	if not stack_size then
		local prototype = prototypes.item[item_name]
		if prototype then
			stack_size = prototype.stack_size
			stack_sizes_cache[item_name] = stack_size
		else
			error("Unknown item name: " .. item_name .. ".")
		end
	end
	return stack_size
end

--#endregion

--#region ENTITY

---@class rgb
---@field r number
---@field g number
---@field b number

---@param entity table
---@param text string
---@param color? rgb
---@param offset? vector2
lib.entity_say = function(entity, text, color, offset)
	log((entity.name or "someone") .. " said: " .. text)

	local DEBUG = true
	if not DEBUG then
		return
	end

	local entityPosition = entity.position

	if offset then
		entityPosition.y = entityPosition.y + (offset.y or 0)
		entityPosition.x = entityPosition.x + (offset.x or 0)
	end
	rendering.draw_text({
		text = text,
		surface = entity.surface,
		target = entityPosition,
		color = color or { r = 255, g = 255, b = 255 },
		time_to_live = 60 * 5,
	})
end

lib.add_to_update_schedule = function(self)
	local bucket_index = self.unit_number % consts.DEPOT_UPDATE_INTERVAL
	local bucket = script_data.depot_update_buckets[bucket_index]
	if not bucket then
		bucket = {}
		script_data.depot_update_buckets[bucket_index] = bucket
	end
	bucket[self.unit_number] = self
end

lib.get_contents_dict = function(inventory)
	local contents_list = inventory.get_contents()
	local contents_dict = {}
	for _, item in pairs(contents_list) do
		local contents_by_quality = contents_dict[item.name] or {}
		contents_by_quality[item.quality] = item.count + (contents_by_quality[item.quality] or 0)
		contents_dict[item.name] = contents_by_quality
	end
	return contents_dict
end

--#endregion

--#region MAP

lib.add_to_map = function(self, list)
	local force_name = self.entity.force.name
	local force_depots = list[force_name]
	if not force_depots then
		force_depots = {}
		list[force_name] = force_depots
	end

	local surface_name = self.entity.surface.name
	local surface_depots = force_depots[surface_name]
	if not surface_depots then
		surface_depots = {}
		force_depots[surface_name] = surface_depots
	end
	surface_depots[self.unit_number] = self
end

lib.get_depots_on_map = function(surface, force, list)
	local force_depots = list[force.name]
	return force_depots and force_depots[surface.name]
end

--#endregion

--#region GUI

lib.get_force_color = function(force)
	local _, player = next(force.players)
	if player then
		return player.color
	end
	return { r = 0, g = 0, b = 0 } -- empty color
end

lib.get_or_make_relative_gui = function(player)
	local relative_gui = player.gui.relative.request_depot_gui
	if relative_gui then
		return relative_gui
	end

	relative_gui = player.gui.relative.add({
		type = "frame",
		name = "request_depot_gui",
		caption = "Deliveries",
		direction = "vertical",
		anchor = {
			gui = defines.relative_gui_type.container_gui,
			name = "long-range-delivery-drone-request-depot",
			--position = defines.relative_gui_position.bottom
			position = defines.relative_gui_position.right,
			--position = defines.relative_gui_position.left
		},
	})
	relative_gui.style.vertically_stretchable = false
	relative_gui.style.horizontally_stretchable = false

	local inner = relative_gui.add({
		type = "frame",
		direction = "vertical",
		style = "inside_deep_frame",
	})
	inner.style.vertically_stretchable = false

	local scroll = inner.add({ type = "scroll-pane", style = "naked_scroll_pane", horizontal_scroll_policy = "never" })

	local table = scroll.add({
		type = "table",
		column_count = 2,
	})
	table.style.horizontal_spacing = 0
	table.style.vertical_spacing = 0

	return relative_gui
end

-- no idea what this accesses but i'm not touching it
lib.get_panel_table = function(gui)
	return gui.children[1].children[1].children[1]
end

local add_or_update_scheduled = function(scheduled, table)
	for name, quality_count in pairs(scheduled) do
		for quality, count in pairs(quality_count) do
			local button = table[name]
				or table.add({ -- TODO add quality icon? Using choose-elem-button rather than sprite-button?
					type = "sprite-button",
					name = name,
					tags = { name = name, quality = quality },
					sprite = "item/" .. name,
					style = "transparent_slot",
				})
			button.number = count
		end
	end
	for k, child in pairs(table.children) do
		local name = child.name
		local quality = child.tags and child.tags.quality
		if name and quality and not (scheduled[name] and scheduled[name][quality]) then
			child.destroy()
		end
	end
end

lib.add_or_update_targeting_panel = function(targeting_me, gui)
	local frame = gui[tostring(targeting_me.unit_number)]
	if not frame then
		frame = gui.add({
			type = "frame",
			direction = "vertical",
			style = "train_with_minimap_frame",
			name = tostring(targeting_me.unit_number),
		})
		--frame.style.width = 215
		--frame.style.height = 215 + 12 + 28
		local button = frame.add({
			type = "button",
			style = "locomotive_minimap_button",
			name = "click_to_open_on_map",
			tags = { unit_number = targeting_me.unit_number },
		})
		button.style.width = 176
		button.style.height = 176
		--button.style.horizontally_stretchable = true
		--button.style.vertically_stretchable = true
		local camera = button.add({
			type = "minimap",
			position = targeting_me.position or { 0, 0 },
			zoom = 1,
		})
		camera.entity = targeting_me.entity
		local size = 884
		camera.style.minimal_width = 176
		camera.style.minimal_height = 176
		camera.style.horizontally_stretchable = true
		camera.style.vertically_stretchable = true
		camera.ignored_by_interaction = true
		local sprite = targeting_me:get_minimap_icon()
		if sprite then
			local icon = camera.add({ type = "sprite", sprite = sprite })
			icon.style.padding = { (191 - 32) / 2, (191 - 32) / 2 }
		end
		if targeting_me.get_distance_to_target then
			local label = camera.add({
				type = "label",
				name = "distance_to_target",
			})
			label.style.left_padding = 4
			label.style.font = "count-font"
			label.style.horizontal_align = "center"
			label.style.width = 172
			label.style.vertical_align = "bottom"
			label.style.height = 172
		end
		frame.add({ type = "table", column_count = 5 })
	end
	local label = frame.children[1].children[1].distance_to_target
	if label then
		label.caption = "[" .. math.ceil(targeting_me:get_distance_to_target()) .. "m]"
	end
	local table = frame.children[2]
	--local deep = frame.add{type = "frame", style = "deep_frame_in_shallow_frame"}
	add_or_update_scheduled(targeting_me.scheduled, table)
end

--#endregion

return lib
