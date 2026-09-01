local constants = require("scripts.constants")
local runtime = require("scripts.inserter_runtime")

local gui = {}

local function root(player)
  return player.gui.relative[constants.gui.root]
end

local function destroy(player)
  local element = root(player)
  if element and element.valid then
    element.destroy()
  end
end

local function read_player_record(player_index)
  local player_state = storage.twi.players[player_index]
  if not player_state then return nil end
  return storage.twi.entities[player_state.unit_number]
end

local function read_player_state(player_index)
  return storage.twi.players[player_index]
end

local function remaining_edit_target(record)
  for player_index in pairs(record.open_players or {}) do
    local player_state = read_player_state(player_index)
    if player_state and player_state.unit_number == record.unit_number then
      return player_state.edit_target or constants.direction_forward
    end
  end
  return nil
end

local function finish_player_edit(record, player_index, tick)
  record.open_players[player_index] = nil
  record.open_count = math.max((record.open_count or 1) - 1, 0)

  local target = remaining_edit_target(record)
  if target then
    record.edit_target = target
    runtime.apply_profile_for_edit(record, target)
  else
    record.edit_target = nil
    runtime.normalize_forward(record, tick)
  end
end

local function find_child(parent, name)
  if not (parent and parent.valid) then return nil end
  local direct = parent[name]
  if direct then return direct end
  for _, child in pairs(parent.children) do
    local found = find_child(child, name)
    if found then return found end
  end
  return nil
end

local function refresh_enabled_state(frame, enabled)
  local function set_children(parent)
    for _, child in pairs(parent.children) do
      if child.name ~= constants.gui.enabled then
        child.enabled = enabled
        set_children(child)
      end
    end
  end
  set_children(frame)
end

local function create(player, entity, record)
  destroy(player)

  local position = defines.relative_gui_position.right
  if script.active_mods and script.active_mods["Smart_Inserters"] then
    position = defines.relative_gui_position.left
  end

  local frame = player.gui.relative.add{
    type = "frame",
    name = constants.gui.root,
    caption = {"two-way-inserter.gui-title"},
    direction = "vertical",
    anchor = {
      gui = defines.relative_gui_type.inserter_gui,
      position = position,
      name = entity.name
    }
  }

  frame.style.padding = 8
  frame.style.minimal_width = 260

  frame.add{
    type = "checkbox",
    name = constants.gui.enabled,
    caption = {"two-way-inserter.enabled"},
    state = record.enabled
  }

  local target_flow = frame.add{ type = "flow", direction = "horizontal" }
  target_flow.add{ type = "label", caption = {"two-way-inserter.edit-target"} }
  target_flow.add{
    type = "drop-down",
    name = constants.gui.edit_target,
    items = {
      {"two-way-inserter.edit-target-forward"},
      {"two-way-inserter.edit-target-reverse"}
    },
    selected_index = 1
  }

  refresh_enabled_state(frame, record.enabled)
end

local function selected_target(element)
  if element and element.selected_index == 2 then
    return constants.direction_reverse
  end
  return constants.direction_forward
end

local function set_selected_target(player, target)
  local frame = root(player)
  if not (frame and frame.valid) then return end
  local target_drop_down = find_child(frame, constants.gui.edit_target)
  if target_drop_down then
    target_drop_down.selected_index = target == constants.direction_reverse and 2 or 1
  end
end

local function save_current_profile(player)
  local record = read_player_record(player.index)
  local frame = root(player)
  if not (record and frame and frame.valid) then return end

  local enabled_checkbox = find_child(frame, constants.gui.enabled)
  if not enabled_checkbox then return end

  local enabled = enabled_checkbox.state
  runtime.set_enabled(record, enabled)

  local player_state = read_player_state(player.index)
  local target = player_state and player_state.edit_target or constants.direction_forward
  runtime.save_profile(record, target)
end

function gui.on_opened(event)
  local player = game.get_player(event.player_index)
  if not (player and event.entity and event.entity.valid and event.entity.type == "inserter") then return end

  runtime.init_storage()
  local previous = read_player_record(player.index)
  if previous then
    save_current_profile(player)
    finish_player_edit(previous, player.index, event.tick)
  end

  local record = runtime.ensure(event.entity, event.tick)
  if not record then return end

  storage.twi.players[player.index] = {
    unit_number = record.unit_number,
    edit_target = constants.direction_forward
  }
  record.open_players[player.index] = true
  record.open_count = (record.open_count or 0) + 1
  record.edit_target = constants.direction_forward

  runtime.normalize_forward(record, event.tick)
  create(player, event.entity, record)
end

function gui.on_closed(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local record = read_player_record(player.index)
  if record then
    save_current_profile(player)
    finish_player_edit(record, player.index, event.tick)
  end

  storage.twi.players[player.index] = nil
  destroy(player)
end

function gui.on_checked_state_changed(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local frame = root(player)
  if not (frame and frame.valid and event.element and event.element.valid) then return end
  if event.element.name == constants.gui.enabled then
    save_current_profile(player)
    if not event.element.state then
      local record = read_player_record(player.index)
      local player_state = read_player_state(player.index)
      if record and runtime.apply_profile_for_edit(record, constants.direction_forward) then
        if player_state then
          player_state.edit_target = constants.direction_forward
        end
        record.edit_target = constants.direction_forward
        set_selected_target(player, constants.direction_forward)
      end
    end
    refresh_enabled_state(frame, event.element.state)
  end
end

function gui.on_selection_state_changed(event)
  if not (event.element and event.element.valid and event.element.name == constants.gui.edit_target) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local record = read_player_record(player.index)
  local player_state = read_player_state(player.index)
  if not (record and player_state) then return end

  save_current_profile(player)
  local target = selected_target(event.element)
  if runtime.apply_profile_for_edit(record, target) then
    player_state.edit_target = target
    record.edit_target = target
  else
    set_selected_target(player, player_state.edit_target)
  end
end

function gui.on_text_changed(event)
end

function gui.on_elem_changed(event)
end

return gui
