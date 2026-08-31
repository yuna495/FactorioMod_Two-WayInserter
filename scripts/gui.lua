local constants = require("scripts.constants")
local profiles = require("scripts.profiles")
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

local function filter_slot_name(index)
  return constants.gui.reverse_filter_prefix .. index
end

local function mode_index(mode)
  return mode == "blacklist" and 2 or 1
end

local function selected_mode(index)
  return index == 2 and "blacklist" or "whitelist"
end

local function build_filter_value(filter)
  if not filter or not filter.name then return nil end
  return {
    name = filter.name,
    quality = filter.quality or "normal"
  }
end

local function read_player_record(player_index)
  local player_state = storage.twi.players[player_index]
  if not player_state then return nil end
  return storage.twi.entities[player_state.unit_number]
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

  frame.add{ type = "line" }

  frame.add{
    type = "label",
    caption = {"two-way-inserter.reverse-section"}
  }

  frame.add{
    type = "checkbox",
    name = constants.gui.reverse_use_filters,
    caption = {"two-way-inserter.reverse-use-filters"},
    state = record.reverse.use_filters
  }

  local mode_flow = frame.add{ type = "flow", direction = "horizontal" }
  mode_flow.add{ type = "label", caption = {"two-way-inserter.filter-mode"} }
  mode_flow.add{
    type = "drop-down",
    name = constants.gui.reverse_filter_mode,
    items = {
      {"two-way-inserter.filter-mode-whitelist"},
      {"two-way-inserter.filter-mode-blacklist"}
    },
    selected_index = mode_index(record.reverse.filter_mode)
  }

  local slots = profiles.filter_count(entity)
  if slots > 0 then
    local table_element = frame.add{ type = "table", column_count = 5 }
    for index = 1, slots do
      local button = table_element.add{
        type = "choose-elem-button",
        name = filter_slot_name(index),
        elem_type = "item-with-quality"
      }
      button.elem_value = build_filter_value(record.reverse.filters[index])
    end
  else
    frame.add{ type = "label", caption = {"two-way-inserter.no-filter-slots"} }
  end

  local stack_flow = frame.add{ type = "flow", direction = "horizontal" }
  stack_flow.add{ type = "label", caption = {"two-way-inserter.stack-size"} }
  stack_flow.add{
    type = "textfield",
    name = constants.gui.reverse_stack_size,
    text = tostring(record.reverse.stack_size_override or 0),
    numeric = true,
    allow_decimal = false,
    allow_negative = false
  }

  refresh_enabled_state(frame, record.enabled)
end

local function save_reverse_from_gui(player)
  local record = read_player_record(player.index)
  local frame = root(player)
  if not (record and frame and frame.valid) then return end

  local enabled_checkbox = find_child(frame, constants.gui.enabled)
  local reverse_use_filters = find_child(frame, constants.gui.reverse_use_filters)
  local reverse_filter_mode = find_child(frame, constants.gui.reverse_filter_mode)
  local reverse_stack_size = find_child(frame, constants.gui.reverse_stack_size)
  if not (enabled_checkbox and reverse_use_filters and reverse_filter_mode and reverse_stack_size) then
    return
  end

  local enabled = enabled_checkbox.state
  runtime.set_enabled(record, enabled)

  record.reverse.use_filters = reverse_use_filters.state
  record.reverse.filter_mode = selected_mode(reverse_filter_mode.selected_index)

  local stack_text = reverse_stack_size.text
  record.reverse.stack_size_override = tonumber(stack_text) or 0

  record.reverse.filters = record.reverse.filters or {}
  local slots = profiles.filter_count(record.entity)
  for index = 1, slots do
    local button = find_child(frame, filter_slot_name(index))
    local value = button and button.elem_value or nil
    if value and value.name then
      record.reverse.filters[index] = {
        name = value.name,
        quality = value.quality or "normal"
      }
    else
      record.reverse.filters[index] = nil
    end
  end

  profiles.sync_positions(record)
end

function gui.on_opened(event)
  local player = game.get_player(event.player_index)
  if not (player and event.entity and event.entity.valid and event.entity.type == "inserter") then return end

  runtime.init_storage()
  local previous = read_player_record(player.index)
  if previous then
    save_reverse_from_gui(player)
    runtime.save_forward(previous)
    previous.open_players[player.index] = nil
    previous.open_count = math.max((previous.open_count or 1) - 1, 0)
    runtime.normalize_forward(previous, event.tick)
  end

  local record = runtime.ensure(event.entity, event.tick)
  if not record then return end

  storage.twi.players[player.index] = { unit_number = record.unit_number }
  record.open_players[player.index] = true
  record.open_count = (record.open_count or 0) + 1

  runtime.normalize_forward(record, event.tick)
  create(player, event.entity, record)
end

function gui.on_closed(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local record = read_player_record(player.index)
  if record then
    save_reverse_from_gui(player)
    runtime.save_forward(record)
    record.open_players[player.index] = nil
    record.open_count = math.max((record.open_count or 1) - 1, 0)
    runtime.normalize_forward(record, event.tick)
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
    save_reverse_from_gui(player)
    refresh_enabled_state(frame, event.element.state)
  elseif event.element.name == constants.gui.reverse_use_filters then
    save_reverse_from_gui(player)
  end
end

function gui.on_selection_state_changed(event)
  if event.element and event.element.valid and event.element.name == constants.gui.reverse_filter_mode then
    local player = game.get_player(event.player_index)
    if player then save_reverse_from_gui(player) end
  end
end

function gui.on_text_changed(event)
  if event.element and event.element.valid and event.element.name == constants.gui.reverse_stack_size then
    local player = game.get_player(event.player_index)
    if player then save_reverse_from_gui(player) end
  end
end

function gui.on_elem_changed(event)
  if not (event.element and event.element.valid) then return end
  if string.sub(event.element.name, 1, #constants.gui.reverse_filter_prefix) == constants.gui.reverse_filter_prefix then
    local player = game.get_player(event.player_index)
    if player then save_reverse_from_gui(player) end
  end
end

return gui
