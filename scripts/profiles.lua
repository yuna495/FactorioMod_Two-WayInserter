local profiles = {}

local function copy_position(position)
  if not position then return nil end
  return { x = position.x or position[1], y = position.y or position[2] }
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

function profiles.copy_position(position)
  return copy_position(position)
end

function profiles.copy_filter(filter)
  return copy_filter(filter)
end

function profiles.copy_filters(filters)
  return copy_filters(filters)
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
    pickup_position = copy_position(forward.drop_position),
    drop_position = copy_position(forward.pickup_position),
    use_filters = false,
    filter_mode = forward.filter_mode or "whitelist",
    filters = {},
    stack_size_override = 0
  }
end

function profiles.apply(entity, profile)
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
  record.forward.pickup_position = copy_position(record.primary.pickup_position)
  record.forward.drop_position = copy_position(record.primary.drop_position)
  record.reverse.pickup_position = copy_position(record.primary.drop_position)
  record.reverse.drop_position = copy_position(record.primary.pickup_position)
end

function profiles.capture_forward(record)
  local entity = record.entity
  if not (entity and entity.valid) then return end
  local captured = profiles.capture(entity)
  record.primary.pickup_position = copy_position(captured.pickup_position)
  record.primary.drop_position = copy_position(captured.drop_position)
  record.forward = captured
  profiles.sync_positions(record)
end

return profiles
