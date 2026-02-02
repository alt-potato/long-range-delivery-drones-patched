local consts = require("lib.global").consts
local global = require("lib.global")

local Depot = require("script.depot-logic")
local RequestDepot = require("script.request-depot-logic")

local lib = {}

local depot_created = function(event)
	-- log("depot_created")
	local entity = event.source_entity
	if not (entity and entity.valid) then
		return
	end
	local depot = Depot.new(entity)
	depot.inventory.set_filter(1, consts.DRONE_NAME)
end

local request_depot_created = function(event)
	-- log("request_depot_created")
	local entity = event.source_entity
	if not (entity and entity.valid) then
		return
	end
	local depot = RequestDepot.new(entity)
end

local triggers = {
	["long-range-delivery-drone-depot-created"] = depot_created,
	["long-range-delivery-drone-request-depot-created"] = request_depot_created,
}

local on_script_trigger_effect = function(event)
	local effect_id = event.effect_id
	local trigger = triggers[effect_id]
	if trigger then
		trigger(event)
	end
end

local on_runtime_mod_setting_changed = function(event)
	-- dynamically set runtime settings
	if event.setting == "long-range-delivery-drones-patched-drone-attrition-rate" then
		global.ATTRITION_RATE = settings.global["long-range-delivery-drones-patched-drone-attrition-rate"].value
	end
end

local update_request_depots = function(tick)
	local index = global.data.next_request_depot_update_index
	if not index and tick % consts.DEPOT_UPDATE_BREAK_TIME ~= 0 then
		return
	end
	-- log("update_request_depots: (" .. (tick or "nil") .. "," .. (index or "nil") .. ")")
	-- log("data: " .. serpent.block(global.data))

	local unit_number, req_depot = next(global.data.request_depots, index)
	if not unit_number then
		global.data.next_request_depot_update_index = nil
		return
	end

	if req_depot then
		if req_depot:update() then
			global.data.request_depots[unit_number] = nil
			global.data.next_request_depot_update_index = nil
		else
			req_depot:say(unit_number)
			global.data.next_request_depot_update_index = unit_number
		end
	else
		log("request depot " .. unit_number .. "is nil?")
		global.data.next_request_depot_update_index = nil
	end
end

local update_depots = function(tick)
	local index = global.data.next_depot_update_index
	if not index and tick % consts.DEPOT_UPDATE_BREAK_TIME ~= 0 then
		return
	end
	-- log("update_depots: (" .. (tick or "nil") .. "," .. (index or "nil") .. ")")
	-- log("data: " .. serpent.block(global.data))

	local unit_number, depot = next(global.data.depots, index)
	if not unit_number then
		global.data.next_depot_update_index = nil
		return
	end
	if depot then
		-- log("updating depot " .. unit_number .. "...")
		if depot:update() then
			global.data.depots[unit_number] = nil
			global.data.next_depot_update_index = nil
		else
			depot:say(unit_number)
			global.data.next_depot_update_index = unit_number
		end
	else
		log("depot " .. unit_number .. "is nil?")
		global.data.next_depot_update_index = nil
	end
end

local update_drones = function(tick)
	local drones_to_update = global.data.drone_update_schedule[tick]
	if not drones_to_update then
		return
	end
	local drones = global.data.drones
	for unit_number, bool in pairs(drones_to_update) do
		local drone = drones[unit_number]
		if drone then
			if drone:update() then
				drones[unit_number] = nil
			end
		end
	end
	global.data.drone_update_schedule[tick] = nil
end

local update_player_opened = function(player)
	if player.opened_gui_type ~= defines.gui_type.entity then
		return true
	end

	local opened = player.opened
	if not (opened and opened.valid) then
		return true
	end

	local unit_number = opened.unit_number
	if not unit_number then
		return true
	end

	local request_depot = global.data.request_depots[unit_number]
	if not request_depot then
		return true
	end

	request_depot:update_gui(player)
end

local update_guis = function(tick)
	if not (global.data.gui_updates and next(global.data.gui_updates)) then
		return
	end
	local players = game.players
	for player_index, player in pairs(global.data.gui_updates) do
		if (player_index + tick) % consts.GUI_UPDATE_INTERVAL == 0 then
			if update_player_opened(player) then
				global.data.gui_updates[player_index] = nil
			end
		end
	end
end

local on_tick = function(event)
	local tick = event.tick
	update_request_depots(tick)
	update_depots(tick)
	update_drones(tick)
	update_guis(tick)
end

local on_gui_opened = function(event)
	-- log("on_gui_opened")
	local entity = event.entity
	if not (entity and entity.valid) then
		return
	end
	local request_depot = global.data.request_depots[entity.unit_number]
	if not request_depot then
		return
	end

	local player = game.get_player(event.player_index)
	if not player then
		return
	end

	global.data.gui_updates = global.data.gui_updates or {}
	global.data.gui_updates[player.index] = player

	request_depot:update_gui(player)
end

local open_on_map = function(player, entity)
	-- log("open_on_map")
	if not (entity and entity.valid) then
		return
	end
	player.opened = nil
	player.set_controller({
		type = defines.controllers.remote,
		position = entity.position,
		surface = entity.surface,
	})
	player.centered_on = entity
	if entity.type == "logistic-container" then
		player.opened = entity
	end
end

local on_gui_click = function(event)
	-- log("on_gui_click")
	local gui = event.element
	if not (gui and gui.valid) then
		return
	end
	local name = gui.name
	if not (name and name == "click_to_open_on_map") then
		return
	end
	local unit_number = gui.tags.unit_number
	if not unit_number then
		return
	end

	local player = game.get_player(event.player_index)
	if not player then
		return
	end

	local depot = global.data.depots[unit_number]
	if depot then
		open_on_map(player, depot.entity)
	end

	local drone = global.data.drones[unit_number]
	if drone then
		open_on_map(player, drone.entity)
	end
end

lib.events = {
	[defines.events.on_script_trigger_effect] = on_script_trigger_effect,
	[defines.events.on_gui_opened] = on_gui_opened,
	[defines.events.on_gui_click] = on_gui_click,
	[defines.events.on_tick] = on_tick,
	[defines.events.on_runtime_mod_setting_changed] = on_runtime_mod_setting_changed,
}

lib.on_init = function()
	-- log("on_init")
	storage.long_range_delivery_drone = storage.long_range_delivery_drone or global.data
	storage.regenerate_data_migration = true
end

lib.on_load = function()
	-- log("on_load")
	global.data = storage.long_range_delivery_drone or global.data
end

lib.on_configuration_changed = function(changed_data)
	-- log("on_configuration_changed")
	local active_drones = global.data.drones or {}

	global.clear_data()
	storage.long_range_delivery_drone = global.data

	for _, surface in pairs(game.surfaces) do
		-- only destroy orphaned drones (not in old drone tracking table)
		local drones = surface.find_entities_filtered({ name = consts.DRONE_NAME })
		for _, drone in pairs(drones) do
			if not active_drones[drone.unit_number] then
				log(
					"Found orphaned drone "
						.. drone.unit_number
						.. " at position "
						.. drone.position.x
						.. ", "
						.. drone.position.y
						.. " with inventory "
						.. serpent.line(drone.get_inventory(defines.inventory.chest))
						.. ", destroying"
				)
				drone.destroy()
			end
		end
		local depots = surface.find_entities_filtered({ name = "long-range-delivery-drone-depot" })
		for _, depot in pairs(depots) do
			depot_created({ source_entity = depot })
		end
		local request_depots = surface.find_entities_filtered({ name = "long-range-delivery-drone-request-depot" })
		for _, request_depot in pairs(request_depots) do
			request_depot_created({ source_entity = request_depot })
		end
	end
end

return lib
