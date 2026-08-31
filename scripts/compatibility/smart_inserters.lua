local smart_inserters = {}

function smart_inserters.register(handler)
  if not (remote and remote.interfaces and remote.interfaces["Smart_Inserters"]) then
    return false
  end
  if not remote.interfaces["Smart_Inserters"]["on_inserter_arm_changed"] then
    return false
  end

  local ok, event_id = pcall(function()
    return remote.call("Smart_Inserters", "on_inserter_arm_changed")
  end)
  if ok and event_id then
    script.on_event(event_id, handler)
    return true
  end
  return false
end

return smart_inserters
