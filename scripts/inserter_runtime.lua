local constants = require("scripts.constants")
local profiles = require("scripts.profiles")
local state = require("scripts.state")
local smart_inserters = require("scripts.compatibility.smart_inserters")

local runtime = {}

local function read_disabled_by_script(entity)
  local ok, disabled = pcall(function()
    return entity.disabled_by_script
  end)
  if ok then return disabled end
  return false
end

local function write_disabled_by_script(entity, disabled)
  pcall(function()
    entity.disabled_by_script = disabled and true or false
  end)
end

local function notify_arm_changed(record)
  record.suppress_external_arm_changed = true
  smart_inserters.notify_arm_changed(record.entity)
  record.suppress_external_arm_changed = nil
end

function runtime.init_storage()
  state.init()
end

function runtime.rebuild_active_index()
  state.init()
  storage.twi.active = {}
  for unit_number, record in pairs(storage.twi.entities) do
    if record.entity and record.entity.valid and record.enabled then
      storage.twi.active[unit_number] = true
    end
  end
end

function runtime.on_removed(entity)
  if state.is_inserter(entity) then
    state.remove(entity.unit_number)
  end
end

function runtime.on_object_destroyed(registration_number)
  state.init()
  local unit_number = storage.twi.destroyed[registration_number]
  if unit_number then
    state.remove(unit_number)
  end
end

local function apply_forward(record, tick)
  profiles.sync_positions(record)
  profiles.apply(record.entity, record.forward)
  record.direction = constants.direction_forward
  record.phase = constants.phase_forward
  record.reverse_probe_reason = nil
  record.reverse_started_tick = 0
  record.last_held_item = profiles.has_held_item(record.entity)
  state.schedule_next_probe(record, tick)
  notify_arm_changed(record)
end

function runtime.normalize_forward(record, tick)
  if not (record and record.entity and record.entity.valid) then return false end
  if profiles.has_held_item(record.entity) then
    return false
  end
  apply_forward(record, tick or game.tick)
  return true
end

function runtime.save_forward(record)
  if not (record and record.entity and record.entity.valid) then return end
  if record.direction == constants.direction_forward and not profiles.has_held_item(record.entity) then
    profiles.capture_forward(record)
  end
end

function runtime.save_profile(record, target)
  if not (record and record.entity and record.entity.valid) then return end
  if target == constants.direction_reverse then
    profiles.capture_reverse(record)
  else
    profiles.capture_forward(record)
  end
end

function runtime.apply_profile_for_edit(record, target)
  if not (record and record.entity and record.entity.valid) then return false end
  profiles.sync_positions(record)
  record.edit_target = target
  if target == constants.direction_reverse then
    profiles.apply(record.entity, record.reverse)
    record.direction = constants.direction_reverse
    record.phase = constants.phase_forward
  else
    profiles.apply(record.entity, record.forward)
    record.direction = constants.direction_forward
    record.phase = constants.phase_forward
  end
  record.reverse_probe_reason = nil
  record.reverse_started_tick = 0
  record.last_held_item = profiles.has_held_item(record.entity)
  if record.open_count and record.open_count > 0 and record.enabled then
    write_disabled_by_script(record.entity, true)
  end
  notify_arm_changed(record)
  return true
end

function runtime.begin_gui_edit(record, tick)
  if not (record and record.entity and record.entity.valid) then return false end
  if (record.open_count or 0) <= 1 then
    record.editor_was_disabled_by_script = read_disabled_by_script(record.entity)
  end
  if record.enabled then
    write_disabled_by_script(record.entity, true)
  end
  return runtime.apply_profile_for_edit(record, constants.direction_forward)
end

function runtime.refresh_gui_pause(record)
  if not (record and record.entity and record.entity.valid) then return false end
  if record.enabled then
    write_disabled_by_script(record.entity, true)
  elseif record.editor_was_disabled_by_script ~= nil then
    write_disabled_by_script(record.entity, record.editor_was_disabled_by_script)
  end
  return true
end

function runtime.end_gui_edit(record, tick)
  if not (record and record.entity and record.entity.valid) then return false end
  runtime.apply_profile_for_edit(record, constants.direction_forward)
  record.edit_target = nil
  if record.editor_was_disabled_by_script ~= nil then
    write_disabled_by_script(record.entity, record.editor_was_disabled_by_script)
    record.editor_was_disabled_by_script = nil
  end
  return true
end

local function start_reverse_probe(record, tick, reason)
  if profiles.has_held_item(record.entity) then return end
  if record.direction == constants.direction_forward then
    profiles.capture_forward(record)
  end
  profiles.sync_positions(record)
  profiles.apply(record.entity, record.reverse)
  record.direction = constants.direction_reverse
  record.phase = constants.phase_reverse_probe
  record.reverse_probe_reason = reason
  record.reverse_started_tick = tick
  record.last_held_item = false
end

local function reverse_probe_timeout(record)
  if record.reverse_probe_reason == "after_forward" then
    return constants.after_forward_reverse_probe_timeout_ticks
  end
  return constants.idle_reverse_probe_timeout_ticks
end

local function has_active_editor(record)
  local player_index = record.editor_player_index
  if not player_index then return false end

  local player = game.get_player(player_index)
  if not (player and player.connected) then return false end

  local player_state = storage.twi.players[player_index]
  if not (player_state and player_state.unit_number == record.unit_number) then
    return false
  end

  local ok, opened = pcall(function()
    return player.opened
  end)
  if not (ok and opened) then return false end

  local valid_ok, valid = pcall(function()
    return opened.valid
  end)
  return valid_ok and valid and opened == record.entity
end

local function tick_record(record, tick)
  local entity = record.entity
  if not (entity and entity.valid) then
    state.remove(record.unit_number)
    return
  end

  local held = profiles.has_held_item(entity)

  if record.open_count and record.open_count > 0 then
    if not has_active_editor(record) then
      local player_index = record.editor_player_index
      if player_index then
        storage.twi.players[player_index] = nil
      end
      record.open_players = {}
      record.open_count = 0
      record.editor_player_index = nil
      runtime.end_gui_edit(record, tick)
    end
    return
  end

  if not record.enabled then
    return
  end

  if record.phase == constants.phase_forward then
    if record.direction ~= constants.direction_forward then
      if not held then
        apply_forward(record, tick)
      end
      return
    end

    if held then
      record.last_forward_activity_tick = tick
    elseif record.last_held_item then
      record.last_forward_activity_tick = tick
      start_reverse_probe(record, tick, "after_forward")
    elseif tick >= (record.next_probe_tick or 0) then
      start_reverse_probe(record, tick, "idle")
    end
  elseif record.phase == constants.phase_reverse_probe then
    if held then
      record.phase = constants.phase_reverse_transfer
    elseif tick - (record.reverse_started_tick or tick) >= reverse_probe_timeout(record) then
      apply_forward(record, tick)
    end
  elseif record.phase == constants.phase_reverse_transfer then
    if not held and record.last_held_item then
      apply_forward(record, tick)
    end
  else
    if not held then
      apply_forward(record, tick)
    end
  end

  record.last_held_item = profiles.has_held_item(entity)
end

function runtime.on_tick(tick)
  state.init()
  for unit_number in pairs(storage.twi.active) do
    local record = storage.twi.entities[unit_number]
    if record then
      tick_record(record, tick)
    else
      storage.twi.active[unit_number] = nil
    end
  end
end

function runtime.on_entity_cloned(source, destination)
  state.init()
  if not (state.is_inserter(source) and state.is_inserter(destination)) then return end
  local source_record = storage.twi.entities[source.unit_number]
  if not source_record then return end

  local record = state.ensure(destination, game.tick)
  record.enabled = source_record.enabled
  record.primary = {
    base_position = profiles.copy_position(destination.position),
    direction = source_record.primary.direction or source_record.forward.direction or source.direction,
    pickup_position = profiles.copy_position(source_record.primary.pickup_position),
    drop_position = profiles.copy_position(source_record.primary.drop_position)
  }
  record.forward = profiles.capture(destination)
  record.forward.use_filters = source_record.forward.use_filters
  record.forward.filter_mode = source_record.forward.filter_mode
  record.forward.filters = profiles.copy_filters(source_record.forward.filters)
  record.forward.stack_size_override = source_record.forward.stack_size_override
  record.reverse = {
    direction = source_record.reverse.direction or profiles.opposite_direction(record.primary.direction),
    pickup_position = profiles.copy_position(source_record.reverse.pickup_position),
    drop_position = profiles.copy_position(source_record.reverse.drop_position),
    use_filters = source_record.reverse.use_filters,
    filter_mode = source_record.reverse.filter_mode,
    filters = profiles.copy_filters(source_record.reverse.filters),
    stack_size_override = source_record.reverse.stack_size_override
  }
  if source_record.reverse_positions_customized ~= nil then
    record.reverse_positions_customized = source_record.reverse_positions_customized
  else
    record.reverse_positions_customized = not profiles.reverse_positions_match_derived(record)
  end
  profiles.sync_positions(record)
  record.direction = constants.direction_forward
  record.phase = constants.phase_forward
  state.set_enabled(record, record.enabled)
  runtime.normalize_forward(record, game.tick)
end

function runtime.on_player_rotated_entity(event)
  state.init()
  local entity = event and event.entity
  if not state.is_inserter(entity) then return end
  local record = storage.twi.entities[entity.unit_number]
  if not record then return end

  if profiles.rotate_record(record, event.previous_direction, entity.direction) then
    record.reverse_probe_reason = nil
    record.reverse_started_tick = 0
    record.last_held_item = profiles.has_held_item(entity)
    state.schedule_next_probe(record, event.tick or game.tick)
    notify_arm_changed(record)
  end
end

function runtime.on_external_arm_changed(event)
  state.init()
  local entity = event and event.entity
  if not state.is_inserter(entity) then return end
  local record = storage.twi.entities[entity.unit_number]
  if not record then return end
  if record.suppress_external_arm_changed then return end

  if record.open_count and record.open_count > 0 then
    runtime.save_profile(record, record.edit_target or constants.direction_forward)
  elseif record.direction == constants.direction_forward then
    if profiles.has_held_item(entity) then return end
    profiles.capture_forward(record)
  end
end

runtime.ensure = state.ensure
runtime.set_enabled = state.set_enabled

return runtime
