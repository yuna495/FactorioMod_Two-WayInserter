local constants = {}

constants.mod_prefix = "twi"

constants.direction_forward = "forward"
constants.direction_reverse = "reverse"

constants.phase_forward = "forward"
constants.phase_reverse_probe = "reverse_probe"
constants.phase_reverse_transfer = "reverse_transfer"

constants.reverse_probe_interval_ticks = 10
constants.after_forward_reverse_probe_timeout_ticks = 8
constants.idle_reverse_probe_timeout_ticks = 60

constants.gui = {
  root = "twi_reverse_root",
  enabled = "twi_enabled",
  reverse_use_filters = "twi_reverse_use_filters",
  reverse_filter_mode = "twi_reverse_filter_mode",
  reverse_stack_size = "twi_reverse_stack_size",
  reverse_filter_prefix = "twi_reverse_filter_"
}

return constants
