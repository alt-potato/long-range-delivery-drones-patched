local helpers = require("lib.helpers")
local consts = require("lib.global").consts
local global = require("lib.global")

---@class RequestDepot
---@field entity LuaEntity
---@field unit_number integer
---@field position vector2
---@field scheduled table
---@field inventory LuaInventory
---@field logistic_point LuaLogisticPoint
---@field targeting_me table
local RequestDepot = {}
RequestDepot.metatable = { __index = RequestDepot }
script.register_metatable("Request_depot", RequestDepot.metatable) -- yes old name i'm not writing a migration script ok

local add_to_depots = function(self)
	global.data.request_depots[self.unit_number] = self
end

RequestDepot.new = function(entity)
	-- log("RequestDepot.new")
	local self = {
		entity = entity,
		unit_number = entity.unit_number,
		position = entity.position,
		scheduled = {},
		inventory = entity.get_inventory(defines.inventory.chest),
		logistic_point = entity.get_logistic_point(defines.logistic_member_index.logistic_container),
		targeting_me = {},
	}
	setmetatable(self, RequestDepot.metatable)

	script.register_on_object_destroyed(entity)
	add_to_depots(self)
	helpers.add_to_update_schedule(self)
	return self
end

RequestDepot.say = function(self, text, y_offset)
	helpers.entity_say(self.entity, text, { r = 1, g = 0.5, b = 0 }, { x = -1, y = -1 + (y_offset or 0) })
end

RequestDepot.add_targeting_me = function(self, other)
	-- log("RequestDepot.add_targeting_me")
	self.targeting_me = self.targeting_me or {}
	self.targeting_me[other.unit_number] = other
end

RequestDepot.remove_targeting_me = function(self, other)
	-- log("RequestDepot.remove_targeting_me")
	self.targeting_me = self.targeting_me or {}
	self.targeting_me[other.unit_number] = nil
end

RequestDepot.get_closest = function(self, depots)
	-- log("RequestDepot.get_closest")
	local closest_depot = nil
	local closest_distance = math.huge
	local position = self.position
	for unit_number, depot in pairs(depots) do
		local distance = helpers.distance_squared(position, depot.position)
		if distance < closest_distance then
			closest_depot = depot
			closest_distance = distance
		end
	end

	if not closest_depot then
		return
	end

	depots[closest_depot.unit_number] = nil
	return closest_depot
end

RequestDepot.try_to_schedule_delivery = function(self, item_name, item_quality, item_count)
	local depots = helpers.get_depots_on_map(self.entity.surface, self.entity.force, global.data.depot_map)
	if not depots then
		self:say("No depots on map :(")
		return
	end

	self:say("Trying to schedule: " .. item_name .. " " .. item_count, 0.5)

	local stack_size = helpers.get_stack_size(item_name)

	local request_count = math.min(item_count, stack_size * consts.MAX_DELIVERY_STACKS)

	local depots_to_check = { {}, {}, {}, {} }

	local check_depot = function(unit_number, depot)
		if depot:get_available_capacity(item_name, item_quality) < stack_size * consts.MIN_DELIVERY_STACKS then
			return
		end

		local inventory_count = depot:get_inventory_count(item_name, item_quality)
		if inventory_count >= request_count then
			depots_to_check[1][unit_number] = depot
			return
		end

		local supply_counts = depot:get_supply_counts(item_name, item_quality)
		if not supply_counts then
			return
		end

		local count = supply_counts["storage"] + supply_counts["passive-provider"] + supply_counts["active-provider"]
		if count >= request_count then
			depots_to_check[2][unit_number] = depot
			return
		end

		if depot.entity.request_from_buffers then
			count = count + supply_counts["buffer"]
			if count >= request_count then
				depots_to_check[3][unit_number] = depot
				return
			end
		end

		if count >= stack_size * consts.MIN_DELIVERY_STACKS then
			depots_to_check[4][unit_number] = depot
			return
		end
	end

	for unit_number, depot in pairs(depots) do
		if not depot.entity.valid then
			depots[unit_number] = nil
		elseif depot:can_handle_request(self) then
			check_depot(unit_number, depot)
		end
	end

	local closest
	for k, list in pairs(depots_to_check) do
		if next(list) then
			closest = self:get_closest(list)
			if closest then
				break
			end
		end
	end
	if not closest then
		return
	end
	local scheduled_count = closest:delivery_requested(self, item_name, item_quality, item_count)
	if scheduled_count == 0 then
		return
	end

	self.scheduled[item_name] = self.scheduled[item_name] or {}
	self.scheduled[item_name][item_quality] = (self.scheduled[item_name][item_quality] or 0) + scheduled_count

    -- log("request scheduled successfully! (probably)")
    -- log(serpent.block(closest))
end

RequestDepot.update_gui = function(self, player)
	local relative_gui = helpers.get_or_make_relative_gui(player)
	local table = helpers.get_panel_table(relative_gui)
	local targeting_me = self.targeting_me or {}

	for unit_number, other in pairs(targeting_me) do
		if not other.entity.valid then
			targeting_me[unit_number] = nil
		else
			helpers.add_or_update_targeting_panel(other, table)
		end
	end

	relative_gui.visible = next(targeting_me) and true or false

	for k, child in pairs(table.children) do
		local name = child.name
		if name and not targeting_me[tonumber(name)] then
			child.destroy()
		end
	end
end

RequestDepot.update = function(self)
	if not self.entity.valid then
		return true
	end
	local contents = helpers.get_contents_dict(self.inventory)
	local scheduled = self.scheduled
	local on_the_way = self.logistic_point.targeted_items_deliver or {}
	local logistic_point = self.logistic_point

	for _, request in pairs(logistic_point.filters or {}) do
		local name = request.name
		local quality = request.quality
		local scheduled_count = scheduled[name] and scheduled[name][quality] or 0
		local container_count = contents[name] and contents[name][quality] or 0
		local on_the_way_count = on_the_way[name] and on_the_way[name][quality] or 0
		local stack_size = helpers.get_stack_size(name)
		local needed = request.count - (container_count + scheduled_count + on_the_way_count)
		local max_request = stack_size * consts.MAX_DELIVERY_STACKS
		local min_request = stack_size * consts.MIN_DELIVERY_STACKS

		if needed >= max_request then
			self:try_to_schedule_delivery(name, quality, max_request)
		elseif request.count > (1.5 * max_request) then
		-- if the request is more than 1.5 times the max, then we will only deliver the max
		elseif needed >= min_request then
			self:try_to_schedule_delivery(name, quality, needed)
		elseif needed > 0 and request.count < min_request then
			self:try_to_schedule_delivery(name, quality, math.min(needed, request.count))
		end
	end
end

return RequestDepot
