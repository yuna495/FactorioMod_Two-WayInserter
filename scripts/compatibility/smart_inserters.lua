local smart_inserters = {}

local function arm_changed_event_id()
  if not (remote and remote.interfaces and remote.interfaces["Smart_Inserters"]) then
    return nil
  end
  if not remote.interfaces["Smart_Inserters"]["on_inserter_arm_changed"] then
    return nil
  end

  local ok, event_id = pcall(function()
    return remote.call("Smart_Inserters", "on_inserter_arm_changed")
  end)
  if ok then return event_id end
  return nil
end

function smart_inserters.register(handler)
  local event_id = arm_changed_event_id()
  if event_id then
    script.on_event(event_id, handler)
    return true
  end
  return false
end

function smart_inserters.notify_arm_changed(entity)
  local event_id = arm_changed_event_id()
  if event_id and entity and entity.valid then
    script.raise_event(event_id, { entity = entity })
    return true
  end
  return false
end

return smart_inserters
