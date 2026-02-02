local lib = {
	consts = {},
	data = {},
}

local MOD_NAME = "long-range-delivery-drones-patched"

lib.consts = {
	-- META

	MOD_NAME = MOD_NAME,
	BASE_PATH = "__" .. MOD_NAME .. "__",

	-- DEPOT

	DEPOT_UPDATE_INTERVAL = 101,
	DEPOT_UPDATE_BREAK_TIME = 61,
	GUI_UPDATE_INTERVAL = 6,

	-- DRONE

	DRONE_MAX_UPDATE_INTERVAL = 300,
	DRONE_MIN_SPEED = 0.01,
	DRONE_ACCELERATION = 1 / (60 * 8),
	DRONE_MAX_SPEED = 0.5,
	DRONE_TURN_SPEED = 1 / (60 * 5),
	DRONE_HEIGHT = 8,
	-- DELIVERY_OFFSET = { 0, -lib.consts.DRONE_HEIGHT },
	DELIVERY_DISTANCE = 25,
	RETURN_DISTANCE = 5,
	DRONE_NAME = "long-range-delivery-drone",
	MAX_DELIVERY_STACKS = 5,
	MIN_DELIVERY_STACKS = 1,
	DEPOT_ORDER_TIMEOUT = 2 * 60 * 60,
	DEPOT_ORDER_MINIMAL_TIME = 60,
}
lib.consts.DELIVERY_OFFSET = { 0, -lib.consts.DRONE_HEIGHT }

lib.ATTRITION_RATE = nil, -- set at runtime, not readable in data stage

lib.data = {
	request_depots = {}, ---@type table<integer, RequestDepot>
	depots = {}, ---@type table<integer, Depot>
	depot_map = {},
	depot_update_buckets = {},
	drones = {}, ---@type Drone[]
	drone_update_schedule = {},
	gui_updates = {},
	next_depot_update_index = nil,
	next_request_depot_update_index = nil,
}

lib.clear_data = function()
	lib.data.request_depots = {}
	lib.data.depots = {}
	lib.data.depot_map = {}
	lib.data.depot_update_buckets = {}
	lib.data.drones = {}
	lib.data.drone_update_schedule = {}
	lib.data.gui_updates = {}
	lib.data.next_depot_update_index = nil
	lib.data.next_request_depot_update_index = nil
end

return lib
