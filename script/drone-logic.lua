local helpers = require("lib.helpers")
local consts = require("lib.global").consts
local global = require("lib.global")

global.ATTRITION_RATE = settings.global["long-range-delivery-drones-patched-drone-attrition-rate"].value

---@class Drone
---@field entity LuaEntity
---@field unit_number integer
---@field scheduled table
---@field needs_fast_update boolean
---@field inventory LuaInventory
---@field state "delivering"|"returning"
---@field shadow table
---@field source_depot Depot?
---@field delivery_target RequestDepot?
---@field tick_to_suicide integer
---@field suicide_orientation number
local Drone = {}
Drone.metatable = { __index = Drone }
script.register_metatable("Drone", Drone.metatable)

Drone.new = function(entity)
	local self = {
		entity = entity,
		unit_number = entity.unit_number,
		scheduled = {},
		inventory = entity.get_inventory(defines.inventory.car_trunk),
		state = "delivering", -- delivering | returning
	}
	setmetatable(self, Drone.metatable)
	script.register_on_object_destroyed(entity)
	global.data.drones[self.unit_number] = self
	self:create_shadow()
	return self
end

Drone.create_shadow = function(self)
	self.shadow = rendering.draw_animation({
		animation = "long-range-delivery-drone-shadow-animation",
		orientation = 0,
		x_scale = 1,
		y_scale = 1,
		tint = nil,
		render_layer = "projectile",
		animation_speed = 1,
		animation_offset = nil,
		orientation_target = nil,
		orientation_target_offset = nil,
		oriented_offset = nil,
		target = self.entity,
		target_offset = { 0, 0 },
		surface = self.entity.surface,
		time_to_live = nil,
		forces = nil,
		players = nil,
		visible = nil,
	})
	self:update_shadow_height()
	self:update_shadow_orientation()
end

Drone.say = function(self, text, tint)
	helpers.entity_say(self.entity, text, tint)
end

-- what is the purpose of this function
Drone.get_minimap_icon = function(self)
	return nil
end

Drone.get_orientation_to_position = function(self, position)
	local origin = self.entity.position
	local dx = position.x - origin.x
	local dy = position.y - origin.y
	local orientation = (math.atan2(dy, dx) / helpers.tau) + 0.25
	if orientation < 0 then
		orientation = orientation + 1
	elseif orientation > 1 then
		orientation = orientation - 1
	end
	return orientation
end

local apply_delivery_offset = function(position)
	return { x = position.x + consts.DELIVERY_OFFSET[1], y = position.y + consts.DELIVERY_OFFSET[2] }
end

Drone.get_delivery_position = function(self)
	return apply_delivery_offset(self.delivery_target.position)
end

Drone.get_distance_to_target = function(self)
	return self:get_distance(self:get_delivery_position())
end

Drone.get_distance = function(self, position)
	local origin = self.entity.position
	local dx = position.x - origin.x
	local dy = position.y - origin.y
	return (dx * dx + dy * dy) ^ 0.5
end

Drone.get_time_to_next_update = function(self)
	if self.needs_fast_update then
		return 1
	end

	local distance
	if self.state == "returning" then
		distance = self:get_distance(self.source_depot.position) - consts.RETURN_DISTANCE
	else
		distance = self:get_distance_to_target() - consts.DELIVERY_DISTANCE
	end
	local time = distance / self.entity.speed
	local ticks = math.floor(time * 0.5)
	if ticks < 1 then
		return 1
	end
	return math.min(ticks, consts.DRONE_MAX_UPDATE_INTERVAL)
end

Drone.schedule_next_update = function(self, time)
	local scheduled = global.data.drone_update_schedule
	local tick = game.tick + time
	local scheduled_drones = scheduled[tick]
	if not scheduled_drones then
		scheduled_drones = {}
		scheduled[tick] = scheduled_drones
	end
	scheduled_drones[self.unit_number] = true
	--self:say(tick - game.tick)
end

Drone.get_movement = function(self, orientation_variation)
	local orientation = self.entity.orientation + ((0.5 - math.random()) * (orientation_variation or 0))
	local speed = self.entity.speed
	local dx = speed * math.cos(helpers.to_rad(orientation))
	local dy = speed * math.sin(helpers.to_rad(orientation))
	return { dx, dy }
end

Drone.suicide = function(self)
	local position = self.entity.position
	local surface = self.entity.surface
	surface.create_entity({
		name = "big-explosion",
		position = position,
		movement = self:get_movement(0.1),
		--movement = {, 0},
		height = consts.DRONE_HEIGHT,
		vertical_speed = 0.1,
		frame_speed = 1,
	})
	surface.create_particle({
		name = "long-range-delivery-drone-dying-particle",
		position = { position.x, position.y + consts.DRONE_HEIGHT },
		movement = self:get_movement(0.1),
		--movement = {, 0},
		height = consts.DRONE_HEIGHT,
		vertical_speed = 0.1,
		frame_speed = 1,
	})
	global.data.drones[self.unit_number] = nil
	self.entity.destroy()
end

Drone.schedule_suicide = function(self)
	if self.delivery_target then
		self.delivery_target:remove_targeting_me(self)
	end
	self.tick_to_suicide = game.tick + math.random(120, 300)
	self.suicide_orientation = self.entity.orientation + ((0.5 - math.random()) * 2)
	self:schedule_next_update(math.random(1, 30))
end

Drone.schedule_return = function(self)
	-- random chance of attrition if ATTRITION_RATE > 0
	local r = math.random()
	if consts.ATTRITION_RATE > 0 and (consts.ATTRITION_RATE >= 1 or r < consts.ATTRITION_RATE) then
		self:say("i am die thank you forever")
		self:schedule_suicide()
		return
	end

	-- if depot is gone, fallback to suicide
	if not self.source_depot or not self.source_depot.entity.valid then
		self:schedule_suicide()
		return
	end
	self:say("Going back")
	self.delivery_target:remove_targeting_me(self)
	self.delivery_target = nil
	self.state = "returning" -- set return status
	self:schedule_next_update(1)
end

local particle_cache = {}
local fallback_name = "long-range-delivery-drone-delivery-particle"
local get_particle_name = function(item_name)
	if particle_cache[item_name] then
		return particle_cache[item_name]
	end

	local particle_name = fallback_name .. "-" .. item_name
	if not prototypes.particle[particle_name] then
		particle_cache[item_name] = fallback_name
		return fallback_name
	end

	particle_cache[item_name] = particle_name
	return particle_name
end

Drone.make_delivery_particle = function(self, item_name)
	local distance = self:get_distance_to_target()
	local position = self.entity.position
	local speed = self.entity.speed
	local time = 5 * math.ceil((distance / (speed * 0.85)) / 5)
	local delivery_height = consts.DRONE_HEIGHT - 0.60
	local vertical_speed = -delivery_height / time
	local source_position = { position.x, position.y + delivery_height }
	local target_position = self:get_delivery_position()

	self.entity.surface.create_particle({
		name = get_particle_name(item_name),
		position = source_position,
		movement = { (target_position.x - source_position[1]) / time, (target_position.y - position.y) / time },
		height = delivery_height,
		vertical_speed = vertical_speed,
		frame_speed = 1,
	})

	return time
end

Drone.deliver_to_target = function(self)
	self:say("Poopin time")

	local delivery_time
	local source_scheduled = self.scheduled
	local name, quality_count = next(source_scheduled)

	-- if there is nothing to deliver, why are we even here?
	if not quality_count then
		self:schedule_suicide()
		return
	end

	local quality, count = next(quality_count)
	if name and quality and count then
		count = math.min(count, helpers.get_stack_size(name))
		local target_scheduled = self.delivery_target.scheduled
		local removed = self.inventory.remove({ name = name, quality = quality, count = count })
		if removed > 0 then
			self.delivery_target.inventory.insert({ name = name, quality = quality, count = removed })
		end

		source_scheduled[name][quality] = source_scheduled[name][quality] - count
		if source_scheduled[name][quality] <= 0 then
			source_scheduled[name][quality] = nil
		end
		if not next(source_scheduled[name]) then
			source_scheduled[name] = nil
		end

		if target_scheduled[name] and target_scheduled[name][quality] then
			target_scheduled[name][quality] = target_scheduled[name][quality] - count
			if target_scheduled[name][quality] <= 0 then
				target_scheduled[name][quality] = nil
			end
			if not next(target_scheduled[name]) then
				target_scheduled[name] = nil
			end
		end

		delivery_time = self:make_delivery_particle(name)
	end

	if not next(self.scheduled) then
		self:schedule_return()
		return
	end

	self:schedule_next_update(math.ceil(delivery_time * 2) + math.random(10, 30))
end

Drone.cleanup = function(self)
	if self.delivery_target then
		local source_scheduled = self.scheduled
		local target_scheduled = self.delivery_target.scheduled
		for name, quality_count in pairs(source_scheduled) do
			for quality, count in pairs(quality_count) do
				source_scheduled[name][quality] = nil
				if not next(source_scheduled[name]) then
					source_scheduled[name] = nil
				end
				target_scheduled[name][quality] = (target_scheduled[name][quality] or count) - count
				if target_scheduled[name][quality] <= 0 then
					target_scheduled[name][quality] = nil
				end
				if not next(target_scheduled[name]) then
					target_scheduled[name] = nil
				end
			end
		end
	end
end

Drone.update_orientation = function(self, target_orientation)
	if self.entity.speed < consts.DRONE_MAX_SPEED then
		return
	end

	local orientation = self.entity.orientation
	if orientation == target_orientation then
		return
	end

	local delta_orientation = target_orientation - orientation
	if delta_orientation < -0.5 then
		delta_orientation = delta_orientation + 1
	elseif delta_orientation > 0.5 then
		delta_orientation = delta_orientation - 1
	end

	if delta_orientation > consts.DRONE_TURN_SPEED then
		self.entity.orientation = orientation + consts.DRONE_TURN_SPEED
		self.needs_fast_update = true
	elseif delta_orientation < -consts.DRONE_TURN_SPEED then
		self.entity.orientation = orientation - consts.DRONE_TURN_SPEED
		self.needs_fast_update = true
	else
		self.entity.orientation = target_orientation
	end
	self:update_shadow_orientation()
end

Drone.update_speed = function(self)
	local speed = self.entity.speed

	if speed < consts.DRONE_MIN_SPEED then
		self.entity.speed = consts.DRONE_MIN_SPEED + consts.DRONE_ACCELERATION
		self:update_shadow_height()
		self.needs_fast_update = true
		return
	end

	if speed < consts.DRONE_MAX_SPEED then
		self.entity.speed = speed + consts.DRONE_ACCELERATION
		self:update_shadow_height()
		self.needs_fast_update = true
	end
end

Drone.update_shadow_height = function(self)
	local shadow = self.shadow
	if not shadow then
		return
	end
	local height = (helpers.logistic_curve(self.entity.speed / consts.DRONE_MAX_SPEED)) * consts.DRONE_HEIGHT
	shadow.target = { entity = self.entity, offset = { height, height } }
end

Drone.update_shadow_orientation = function(self)
	local shadow = self.shadow
	if not shadow then
		return
	end
	shadow.orientation = self.entity.orientation
end

Drone.get_state_description = function(self)
	local text = ""
	local distance = math.ceil(self:get_distance_to_target())
	text = text .. "[color=34,181,255][" .. distance .. "m][/color]"
	for name, quality_count in pairs(self.scheduled) do
		for quality, count in pairs(quality_count) do
			text = text .. " [item=" .. name .. ",quality=" .. quality .. "]"
		end
	end
	return text
end

Drone.update = function(self)
	if not self.entity.valid then
		self:cleanup()
		return true
	end

	if self.tick_to_suicide then
		self:update_orientation(self.suicide_orientation)
		if game.tick >= self.tick_to_suicide then
			self:suicide()
		else
			self:schedule_next_update(1)
		end
		return
	end

	-- get target destination

	local target
	local apply_offset
	local min_arrival_speed
	local arrival_threshold = 5

	if self.state == "returning" then
		target = self.source_depot
		arrival_threshold = consts.RETURN_DISTANCE
	else
		-- default to delivering
		target = self.delivery_target
		apply_offset = apply_delivery_offset
		min_arrival_speed = consts.DRONE_MAX_SPEED
		arrival_threshold = consts.DELIVERY_DISTANCE
	end

	if not target then
		error("NO target?")
	end
	if not target.entity.valid then
		self:schedule_suicide()
		return
	end
	self:say("HI")

	-- if already in position, do action

	local reached_target_speed = not min_arrival_speed or self.entity.speed >= min_arrival_speed
	local target_position = apply_offset and apply_offset(target.position) or target.position
	if reached_target_speed and self:get_distance(target_position) <= arrival_threshold then
		if self.state == "delivering" then
			self:deliver_to_target()
			return
		elseif self.state == "returning" then
			-- arrived at depot, add drone back to depot
			self.source_depot.inventory.insert({ name = consts.DRONE_NAME, count = 1 })
			global.data.drones[self.unit_number] = nil
			self.entity.destroy()
			return true
		else
			-- default to delivering?
			self:deliver_to_target()
			return
		end
	end

	-- if not, route to target destination

	self.needs_fast_update = false
	self:update_speed()
	self:update_orientation(self:get_orientation_to_position(target_position))
	self:schedule_next_update(self:get_time_to_next_update())
end

return Drone
