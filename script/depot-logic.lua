local helpers = require("lib.helpers")
local consts = require("lib.global").consts
local global = require("lib.global")

local Drone = require("script.drone-logic")

local add_to_depots = function(self)
	global.data.depots[self.unit_number] = self
end

---@class Depot
---@field entity LuaEntity
---@field unit_number integer
---@field position vector2
---@field scheduled table
---@field inventory table
---@field logistic_section table
---@field delivery_target RequestDepot
---@field tick_of_recieved_order integer?
local Depot = {}
Depot.metatable = { __index = Depot }
script.register_metatable("Depot", Depot.metatable)

Depot.new = function(entity)
	local self = {
		entity = entity,
		unit_number = entity.unit_number,
		position = entity.position,
		scheduled = {},
		inventory = entity.get_inventory(defines.inventory.chest),
		logistic_section = entity.get_logistic_point(defines.logistic_member_index.logistic_container).get_section(1),
	}
	setmetatable(self, Depot.metatable)
	script.register_on_object_destroyed(entity)
	add_to_depots(self)
	helpers.add_to_map(self, global.data.depot_map)
	helpers.add_to_update_schedule(self)
	return self
end

Depot.get_minimap_icon = function(self)
	return "entity/" .. self.entity.name
end

Depot.say = function(self, text, y_offset)
	helpers.entity_say(self.entity, text, { r = 0, g = 1, b = 1 }, { x = -3, y = -3 + (y_offset or 0) })
end

Depot.get_available_capacity = function(self, item_name, item_quality)
	local stacks = consts.MAX_DELIVERY_STACKS
	for name, quality_count in pairs(self.scheduled) do
		for quality, count in pairs(quality_count) do
			if name ~= item_name or quality ~= item_quality then
				stacks = stacks - math.ceil(count / helpers.get_stack_size(name))
			end
		end
	end
	if not item_name then
		return stacks
	end
	return math.floor(
		stacks * (helpers.get_stack_size(item_name))
			- (self.scheduled[item_name] and self.scheduled[item_name][item_quality] or 0)
	)
end

Depot.update_logistic_filters = function(self)
	local slot_index = 1

	if next(self.scheduled) then
		-- make new logistics section if does not exist
		if not self.logistic_section or not self.logistic_section.valid then
			self.logistic_section =
				self.entity.get_logistic_point(defines.logistic_member_index.logistic_container).add_section()
		end

		if not self.logistic_section.is_manual then
			log("Cannot set slot: section not manual")
			return
		end

		-- preprocess drone slots (in case drone is delivering drones)
		if self.scheduled and self.scheduled[consts.DRONE_NAME] then
			for quality, count in pairs(self.scheduled[consts.DRONE_NAME]) do
				self.logistic_section.set_slot(
					slot_index,
					{ value = { name = consts.DRONE_NAME, quality = quality }, min = 1 + helpers.safe_number(count) }
				)
			end
		else
			-- always allocate at least one drone
			self.logistic_section.set_slot(
				slot_index,
				{ value = { name = consts.DRONE_NAME, quality = "normal" }, min = 1 }
			)
		end

		-- set the rest of the slots based on schedule pairs
		slot_index = slot_index + 1
		for name, quality_count in pairs(self.scheduled) do
			for quality, count in pairs(quality_count) do
				-- ignore drones, since they're already processed
				if name ~= consts.DRONE_NAME then
					self.logistic_section.set_slot(slot_index, {
						value = { name = name, quality = quality },
						min = helpers.safe_number(count),
					})
					slot_index = slot_index + 1
				end
			end
		end
	end

	-- clean up all following slots afterward (but only if logistic section exists)
	if self.logistic_section then
		for i = slot_index, self.logistic_section.filters_count do
			if self.logistic_section.is_manual then
				self.logistic_section.clear_slot(i)
			end
		end
	end
end

Depot.delivery_requested = function(self, request_depot, item_name, item_quality, item_count)
	log('Delivery requested: "' .. item_name .. '" (' .. item_quality .. ") x" .. item_count)
	if self.delivery_target and self.delivery_target ~= request_depot then
		error("Trying to schedule a delivery to another target")
	end
	item_count = math.min(item_count, self:get_available_capacity(item_name, item_quality))
	if item_count == 0 then
		return 0
	end

	if not self.delivery_target then
		self.delivery_target = request_depot
		self.delivery_target:add_targeting_me(self)
	end

	self.tick_of_recieved_order = game.tick

	local scheduled = self.scheduled
	scheduled[item_name] = scheduled[item_name] or {}
	scheduled[item_name][item_quality] = (scheduled[item_name][item_quality] or 0) + item_count
	self:update_logistic_filters()

	return item_count
end

Depot.network_can_satisfy_request = function(self, item_name, count, request_from_buffers)
	local network = self.entity.logistic_network
	return network and network.can_satisfy_request(item_name, count, request_from_buffers)
end

Depot.can_handle_request = function(self, request_depot)
	if self.delivery_target and self.delivery_target ~= request_depot then
		return false
	end

	local logistic_network = self.entity.logistic_network
	if logistic_network and logistic_network == request_depot.entity.logistic_network then
		return false
	end

	local inventory_count = self:get_inventory_count(consts.DRONE_NAME, "normal")
	if inventory_count > 0 then
		return true
	end

	if self:network_can_satisfy_request(consts.DRONE_NAME, 1, self.entity.request_from_buffers) then
		return true
	end

	return false
end

Depot.get_inventory_count = function(self, item_name, item_quality)
	return self.inventory.get_item_count({ name = item_name, quality = item_quality })
		- (self.scheduled[item_name] and self.scheduled[item_name][item_quality] or 0)
end

Depot.transfer_package = function(self, drone)
	local source_inventory = self.inventory
	local source_scheduled = self.scheduled
	local drone_inventory = drone.inventory
	local drone_scheduled = drone.scheduled
	for name, quality_count in pairs(source_scheduled) do
		for quality, count in pairs(quality_count) do
			local removed = source_inventory.remove({ name = name, quality = quality, count = count })
			if removed > 0 then
				drone_inventory.insert({ name = name, quality = quality, count = removed })
			end
			source_scheduled[name][quality] = nil
			if not next(source_scheduled[name]) then
				source_scheduled[name] = nil
			end
			drone_scheduled[name] = drone_scheduled[name] or {}
			drone_scheduled[name][quality] = count
		end
	end
	self:update_logistic_filters()
end

Depot.send_drone = function(self)
	log("Depot.send_drone")
	local target = self.delivery_target
	if not target then
		error("No target?")
	end

	local removed = self.inventory.remove({ name = consts.DRONE_NAME, count = 1 })
	if removed == 0 then
		return
	end

	local force = self.entity.force

	local entity = self.entity.surface.create_entity({
		name = consts.DRONE_NAME,
		position = self.position,
		force = force,
	})
	entity.color = helpers.get_force_color(force)

	force.get_item_production_statistics(self.entity.surface).on_flow(consts.DRONE_NAME, -1)

	local drone = Drone.new(entity)
	self:transfer_package(drone)

	drone.delivery_target = target
	drone.source_depot = self
	target:add_targeting_me(drone)

	self.delivery_target = nil
	self.tick_of_recieved_order = nil
	target:remove_targeting_me(self)

	drone:update()

	return true
end

Depot.cleanup = function(self)
	if self.delivery_target then
		self.delivery_target:remove_targeting_me(self)
		local source_scheduled = self.scheduled
		local target_scheduled = self.delivery_target.scheduled
		for name, quality_count in pairs(source_scheduled) do
			for quality, count in pairs(quality_count) do
				target_scheduled[name][quality] = (target_scheduled[name] and target_scheduled[name][quality] or count)
					- count
				if target_scheduled[name][quality] <= 0 then
					target_scheduled[name][quality] = nil
				end
				if not next(target_scheduled[name]) then
					target_scheduled[name] = nil
				end
				source_scheduled[name][quality] = nil
				if not next(source_scheduled[name]) then
					source_scheduled[name] = nil
				end
			end
		end
	end
end

Depot.has_all_fulfilled = function(self)
	log("Depot.has_all_fulfilled?")
	local scheduled = self.scheduled
	local inventory = self.inventory
	local get_item_count = inventory.get_item_count

	for name, quality_count in pairs(scheduled) do
		for quality, count in pairs(quality_count) do
			local has_count = get_item_count({ name = name, quality = quality })
			if name == consts.DRONE_NAME then
				has_count = has_count - 1
			end
			if has_count < count then
				log("no it is not")
				return
			end
		end
	end
	log("yes it is")
	return true
end

Depot.has_order_timeout = function(self)
	local tick = self.tick_of_recieved_order
	if not tick then
		return
	end
	if game.tick >= (tick + consts.DEPOT_ORDER_TIMEOUT) then
		self:say("Depot order timeout")
		return true
	end
end

Depot.descope_order = function(self)
	local scheduled = self.scheduled
	local inventory = self.inventory
	local get_item_count = inventory.get_item_count
	local target_scheduled = self.delivery_target.scheduled
	for name, quality_count in pairs(scheduled) do
		for quality, count in pairs(quality_count) do
			local has_count = math.min(get_item_count({ name = name, quality = quality }), count)
			scheduled[name][quality] = has_count
			if scheduled[name][quality] <= 0 then
				scheduled[name][quality] = nil
			end
			if not next(scheduled[name]) then
				scheduled[name] = nil
			end
			target_scheduled[name][quality] = (
				(target_scheduled[name] and target_scheduled[name][quality] or 0) - count
			) + has_count
			if target_scheduled[name][quality] <= 0 then
				target_scheduled[name][quality] = nil
			end
			if not next(target_scheduled[name]) then
				target_scheduled[name] = nil
			end
		end
	end
end

Depot.check_minimal_order_time = function(self)
	-- If we are processing too quick, then we might miss some orders the player is setting, so if there is still capacity, we wait a little while
	if not self.tick_of_recieved_order then
		return
	end
	local capacity = self:get_available_capacity()
	if capacity <= 0 then
		return
	end
	local tick = self.tick_of_recieved_order
	if game.tick < (self.tick_of_recieved_order + consts.DEPOT_ORDER_MINIMAL_TIME) then
		return true
	end
end

Depot.check_send_drone = function(self)
	log("Depot.check_send_drone")
	if self:check_minimal_order_time() then
		return
	end

	if self:has_order_timeout() then
		self:descope_order()
		self:send_drone()
		return
	end

	if self:has_all_fulfilled() then
		self:send_drone()
	end
end

Depot.get_state_description = function(self)
	local text = ""
	for name, quality_count in pairs(self.scheduled) do
		for quality, count in pairs(quality_count) do
			text = text .. " [item=" .. name .. ",quality=" .. quality .. "]"
		end
	end
	return text
end

Depot.get_supply_counts = function(self, item_name, item_quality)
	local network = self.entity.logistic_network
	return network and network.get_supply_counts({ name = item_name, quality = item_quality })
end

Depot.update = function(self)
	log("Depot.update " .. self.entity.unit_number)
	if not self.delivery_target then
		log("yo there is no delivery target here")
		log(serpent.block(self))
		return
	end

	log("mimimi")

	if not self.entity.valid then
		log("uhhhhhhhhhhhhhhhhhhh")
		self:cleanup()
		return true
	end

	-- game.print({"", game.tick,  " update depot ", self.entity.unit_number})

	self:say("Hello", 0.5)
	if not self.delivery_target.entity.valid then
		self.delivery_target = nil
		local scheduled = self.scheduled
		for name, quality_count in pairs(scheduled) do
			scheduled[name] = nil
		end
		self:update_logistic_filters()
		return
	end

	self:check_send_drone()
	self:update_logistic_filters()
	self:say("All fulfilled! Send it!", 0.5)
end

return Depot
