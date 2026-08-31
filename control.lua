local runtime = require("scripts.inserter_runtime")
local gui = require("scripts.gui")
local smart_inserters = require("scripts.compatibility.smart_inserters")

script.on_init(function()
  runtime.init_storage()
end)

script.on_configuration_changed(function()
  runtime.init_storage()
  runtime.rebuild_active_index()
end)

script.on_load(function()
  smart_inserters.register(runtime.on_external_arm_changed)
end)

local remove_events = {
  defines.events.on_pre_player_mined_item,
  defines.events.on_robot_pre_mined,
  defines.events.on_entity_died
}

script.on_event(remove_events, function(event)
  runtime.on_removed(event.entity)
end)

script.on_event(defines.events.on_object_destroyed, function(event)
  runtime.on_object_destroyed(event.registration_number)
end)

script.on_event(defines.events.on_entity_cloned, function(event)
  runtime.on_entity_cloned(event.source, event.destination)
end)

script.on_event(defines.events.on_player_rotated_entity, function(event)
  runtime.on_external_arm_changed({ entity = event.entity })
end)

script.on_event(defines.events.on_gui_opened, function(event)
  gui.on_opened(event)
end)

script.on_event(defines.events.on_gui_closed, function(event)
  gui.on_closed(event)
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  gui.on_checked_state_changed(event)
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  gui.on_selection_state_changed(event)
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
  gui.on_text_changed(event)
end)

script.on_event(defines.events.on_gui_confirmed, function(event)
  gui.on_text_changed(event)
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
  gui.on_elem_changed(event)
end)

script.on_nth_tick(1, function(event)
  runtime.on_tick(event.tick)
end)

smart_inserters.register(runtime.on_external_arm_changed)
