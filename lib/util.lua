local lib = {}

-- --- MATH ---

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

-- --- MAP/ENTITY ---

lib.get_force_color = function(force)
	local _, player = next(force.players)
	if player then
		return player.color
	end
	return { r = 0, g = 0, b = 0 } -- empty color
end

return lib
