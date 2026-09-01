local profiles = {}

local function copy_position(position)
  if not position then return nil end
  return { x = position.x or position[1], y = position.y or position[2] }
end

local function mirror_position(position, center)
  local copied = copy_position(position)
  local copied_center = copy_position(center)
  if not (copied and copied_center) then return nil end
  return {
    x = (copied_center.x * 2) - copied.x,
    y = (copied_center.y * 2) - copied.y
  }
end

local function copy_filter(filter)
  if type(filter) == "string" then
    return { name = filter }
  end
  if type(filter) ~= "table" then return nil end
  return {
    name = filter.name,
    quality = filter.quality,
    comparator = filter.comparator
  }
end

local function copy_filters(filters)
  local result = {}
  for index, filter in pairs(filters or {}) do
    result[index] = copy_filter(filter)
  end
  return result
end

local function positions_equal(left, right)
  local left_position = copy_position(left)
  local right_position = copy_position(right)
  if not left_position and not right_position then return true end
  if not (left_position and right_position) then return false end
  return math.abs(left_position.x - right_position.x) < 0.0001
    and math.abs(left_position.y - right_position.y) < 0.0001
end

local direction_names = {
  "north",
  "northnortheast",
  "northeast",
  "eastnortheast",
  "east",
  "eastsoutheast",
  "southeast",
  "southsoutheast",
  "south",
  "southsouthwest",
  "southwest",
  "westsouthwest",
  "west",
  "westnorthwest",
  "northwest",
  "northnorthwest"
}

local direction_indexes = {}
local directions_by_index = {}
local opposite_directions = {}

if defines and defines.direction then
  for index, name in ipairs(direction_names) do
    local direction = defines.direction[name]
    if direction ~= nil then
      direction_indexes[direction] = index - 1
      directions_by_index[index - 1] = direction
    end
  end

  for direction, index in pairs(direction_indexes) do
    opposite_directions[direction] = directions_by_index[(index + 8) % 16]
  end
end

function profiles.copy_position(position)
  return copy_position(position)
end

function profiles.reverse_pickup_position(forward)
  return mirror_position(forward.pickup_position, forward.base_position)
end

function profiles.reverse_drop_position(forward)
  return mirror_position(forward.drop_position, forward.base_position)
end

function profiles.copy_filter(filter)
  return copy_filter(filter)
end

function profiles.copy_filters(filters)
  return copy_filters(filters)
end

function profiles.opposite_direction(direction)
  return opposite_directions[direction] or direction
end

function profiles.positions_equal(left, right)
  return positions_equal(left, right)
end

function profiles.direction_delta(from_direction, to_direction)
  local from_index = direction_indexes[from_direction]
  local to_index = direction_indexes[to_direction]
  if from_index == nil or to_index == nil then return nil end
  return (to_index - from_index) % 16
end

function profiles.rotate_direction(direction, delta)
  local index = direction_indexes[direction]
  if index == nil or delta == nil then return direction end
  return directions_by_index[(index + delta) % 16] or direction
end

function profiles.rotate_position(position, center, delta)
  local copied = copy_position(position)
  local copied_center = copy_position(center)
  if not (copied and copied_center and delta) then return copied end

  local dx = copied.x - copied_center.x
  local dy = copied.y - copied_center.y
  local step = delta % 16

  if step == 0 then
    return { x = copied.x, y = copied.y }
  elseif step == 4 then
    return { x = copied_center.x - dy, y = copied_center.y + dx }
  elseif step == 8 then
    return { x = copied_center.x - dx, y = copied_center.y - dy }
  elseif step == 12 then
    return { x = copied_center.x + dy, y = copied_center.y - dx }
  end

  local angle = step * math.pi / 8
  local cos_angle = math.cos(angle)
  local sin_angle = math.sin(angle)
  return {
    x = copied_center.x + dx * cos_angle - dy * sin_angle,
    y = copied_center.y + dx * sin_angle + dy * cos_angle
  }
end

function profiles.rotate_profile(profile, center, delta)
  if not profile then return end
  profile.direction = profiles.rotate_direction(profile.direction, delta)
  profile.base_position = copy_position(center or profile.base_position)
  profile.pickup_position = profiles.rotate_position(profile.pickup_position, center, delta)
  profile.drop_position = profiles.rotate_position(profile.drop_position, center, delta)
end

function profiles.rotate_record(record, from_direction, to_direction)
  if not (record and record.forward and record.reverse) then return false end
  local delta = profiles.direction_delta(from_direction, to_direction)
  if delta == nil then return false end

  local center = record.primary and record.primary.base_position
    or record.forward.base_position
    or (record.entity and record.entity.valid and copy_position(record.entity.position))
  if not center then return false end

  profiles.rotate_profile(record.forward, center, delta)
  record.primary = record.primary or {}
  record.primary.base_position = copy_position(center)
  record.primary.direction = record.forward.direction
  record.primary.pickup_position = copy_position(record.forward.pickup_position)
  record.primary.drop_position = copy_position(record.forward.drop_position)

  if record.reverse_positions_customized then
    profiles.rotate_profile(record.reverse, center, delta)
  end

  profiles.sync_positions(record)
  return true
end

function profiles.has_held_item(entity)
  local ok, stack = pcall(function()
    return entity.held_stack
  end)
  return ok and stack and stack.valid_for_read
end

function profiles.filter_count(entity)
  local ok, count = pcall(function()
    return entity.prototype.filter_count
  end)
  if ok and type(count) == "number" then
    return count
  end
  return 0
end

function profiles.capture(entity)
  local profile = {
    base_position = copy_position(entity.position),
    direction = entity.direction,
    pickup_position = copy_position(entity.pickup_position),
    drop_position = copy_position(entity.drop_position),
    use_filters = false,
    filter_mode = "whitelist",
    filters = {},
    stack_size_override = 0
  }

  pcall(function()
    profile.use_filters = entity.use_filters and true or false
  end)
  pcall(function()
    profile.filter_mode = entity.inserter_filter_mode or "whitelist"
  end)
  pcall(function()
    profile.stack_size_override = entity.inserter_stack_size_override or 0
  end)

  for index = 1, profiles.filter_count(entity) do
    local ok, filter = pcall(function()
      return entity.get_filter(index)
    end)
    if ok then
      profile.filters[index] = copy_filter(filter)
    end
  end

  return profile
end

function profiles.new_reverse_from_forward(forward)
  return {
    direction = profiles.opposite_direction(forward.direction),
    pickup_position = profiles.reverse_pickup_position(forward),
    drop_position = profiles.reverse_drop_position(forward),
    use_filters = false,
    filter_mode = forward.filter_mode or "whitelist",
    filters = {},
    stack_size_override = 0
  }
end

function profiles.derive_reverse_positions(record)
  record.reverse.direction = profiles.opposite_direction(record.forward.direction)
  record.reverse.pickup_position = profiles.reverse_pickup_position(record.forward)
  record.reverse.drop_position = profiles.reverse_drop_position(record.forward)
end

function profiles.apply(entity, profile)
  if profile.direction then
    pcall(function()
      entity.direction = profile.direction
    end)
  end

  if profile.pickup_position then
    pcall(function()
      entity.pickup_position = copy_position(profile.pickup_position)
    end)
  end

  if profile.drop_position then
    pcall(function()
      entity.drop_position = copy_position(profile.drop_position)
    end)
  end

  pcall(function()
    entity.inserter_filter_mode = profile.filter_mode or "whitelist"
  end)

  for index = 1, profiles.filter_count(entity) do
    local filter = profile.filters and profile.filters[index] or nil
    pcall(function()
      entity.set_filter(index, copy_filter(filter))
    end)
  end

  pcall(function()
    entity.use_filters = profile.use_filters and true or false
  end)

  pcall(function()
    entity.inserter_stack_size_override = tonumber(profile.stack_size_override) or 0
  end)
end

function profiles.sync_positions(record)
  if not record.primary.direction then
    record.primary.direction = record.forward.direction or (record.entity and record.entity.valid and record.entity.direction) or defines.direction.north
  end
  record.primary.base_position = record.primary.base_position or (record.entity and record.entity.valid and copy_position(record.entity.position))
  record.forward.base_position = copy_position(record.primary.base_position)
  record.forward.direction = record.primary.direction
  record.forward.pickup_position = copy_position(record.primary.pickup_position)
  record.forward.drop_position = copy_position(record.primary.drop_position)
  if not record.reverse_positions_customized then
    profiles.derive_reverse_positions(record)
  end
end

function profiles.capture_forward(record)
  local entity = record.entity
  if not (entity and entity.valid) then return end
  local captured = profiles.capture(entity)
  record.primary.base_position = copy_position(captured.base_position)
  record.primary.direction = captured.direction
  record.primary.pickup_position = copy_position(captured.pickup_position)
  record.primary.drop_position = copy_position(captured.drop_position)
  record.forward = captured
  profiles.sync_positions(record)
end

function profiles.capture_reverse(record)
  local entity = record.entity
  if not (entity and entity.valid) then return end
  local captured = profiles.capture(entity)
  local derived = profiles.new_reverse_from_forward(record.forward)
  record.reverse = captured
  record.reverse_positions_customized =
    captured.direction ~= derived.direction
    or not positions_equal(captured.pickup_position, derived.pickup_position)
    or not positions_equal(captured.drop_position, derived.drop_position)
end

function profiles.reverse_positions_match_derived(record)
  if not (record and record.forward and record.reverse) then return true end
  local derived = profiles.new_reverse_from_forward(record.forward)
  return record.reverse.direction == derived.direction
    and positions_equal(record.reverse.pickup_position, derived.pickup_position)
    and positions_equal(record.reverse.drop_position, derived.drop_position)
end

return profiles
