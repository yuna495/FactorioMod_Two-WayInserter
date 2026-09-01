local constants = require("scripts.constants")
local profiles = require("scripts.profiles")

local state = {}

function state.init()
  storage.twi = storage.twi or {}
  storage.twi.entities = storage.twi.entities or {}
  storage.twi.destroyed = storage.twi.destroyed or {}
  storage.twi.players = storage.twi.players or {}
  storage.twi.active = storage.twi.active or {}
end

function state.is_inserter(entity)
  return entity and entity.valid and entity.type == "inserter" and entity.unit_number ~= nil
end

local function register_destroyed(entity, record)
  if record.registration_number then return end
  local registration_number = script.register_on_object_destroyed(entity)
  record.registration_number = registration_number
  storage.twi.destroyed[registration_number] = entity.unit_number
end

function state.schedule_next_probe(record, tick)
  local unit_number = record.unit_number or 0
  record.next_probe_tick = tick + constants.reverse_probe_interval_ticks + (unit_number % constants.reverse_probe_interval_ticks)
end

function state.ensure(entity, tick)
  state.init()
  if not state.is_inserter(entity) then return nil end

  local unit_number = entity.unit_number
  local record = storage.twi.entities[unit_number]
  if record then
    record.entity = entity
    record.primary = record.primary or {}
    record.primary.base_position = record.primary.base_position or profiles.copy_position(entity.position)
    record.primary.direction = record.primary.direction or record.forward and record.forward.direction or entity.direction
    register_destroyed(entity, record)
    return record
  end

  local forward = profiles.capture(entity)
  record = {
    unit_number = unit_number,
    entity = entity,
    enabled = false,
    primary = {
      base_position = profiles.copy_position(forward.base_position),
      direction = forward.direction,
      pickup_position = profiles.copy_position(forward.pickup_position),
      drop_position = profiles.copy_position(forward.drop_position)
    },
    forward = forward,
    reverse = profiles.new_reverse_from_forward(forward),
    direction = constants.direction_forward,
    phase = constants.phase_forward,
    reverse_probe_reason = nil,
    reverse_started_tick = 0,
    last_held_item = profiles.has_held_item(entity),
    last_forward_activity_tick = tick or game.tick,
    next_probe_tick = 0,
    open_players = {},
    open_count = 0
  }
  state.schedule_next_probe(record, tick or game.tick)
  storage.twi.entities[unit_number] = record
  register_destroyed(entity, record)
  return record
end

function state.set_enabled(record, enabled)
  record.enabled = enabled and true or false
  if record.enabled then
    storage.twi.active[record.unit_number] = true
  else
    storage.twi.active[record.unit_number] = nil
  end
end

function state.remove(unit_number)
  state.init()
  local record = storage.twi.entities[unit_number]
  if not record then return end
  if record.registration_number then
    storage.twi.destroyed[record.registration_number] = nil
  end
  storage.twi.active[unit_number] = nil
  storage.twi.entities[unit_number] = nil
end

return state
