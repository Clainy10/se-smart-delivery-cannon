-- Entry point: only wires events. Game logic lives in scripts/logic.lua,
-- everything the player sees lives in scripts/gui.lua.
local logic = require("scripts.logic")
local gui   = require("scripts.gui")

script.on_init(logic.ensure)
script.on_configuration_changed(logic.ensure)

-- Cannon lifecycle ----------------------------------------------------------
local filter = {}
for name in pairs(logic.CANNON_NAMES) do
    filter[#filter + 1] = {filter = "name", name = name}
end
script.on_event(defines.events.on_player_mined_entity, logic.on_removed, filter)
script.on_event(defines.events.on_robot_mined_entity,  logic.on_removed, filter)
script.on_event(defines.events.on_entity_died,         logic.on_removed, filter)
script.on_event(defines.events.script_raised_destroy,  logic.on_removed)

-- Target capture: listen to the same custom input Space Exploration uses ------
local function on_targeter_input(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local data = logic.capture_target(player, event.cursor_position)
    if data then gui.notify_target_set(player, data) end
end

for _, name in pairs(logic.find_targeter_inputs()) do
    script.on_event(name, on_targeter_input)
    logic.targeter_hooked = true
    log("[SmartCannon] hooked custom input: " .. name)
end
if not logic.targeter_hooked then
    log("[SmartCannon] WARNING: no targeter custom input found, manual link fallback enabled")
end

-- GUI -------------------------------------------------------------------------
script.on_event(defines.events.on_gui_opened,        gui.on_opened)
script.on_event(defines.events.on_gui_closed,        gui.on_closed)
script.on_event(defines.events.on_gui_click,         gui.on_click)
script.on_event(defines.events.on_gui_value_changed, gui.on_value_changed)

-- Fallback only: link a chest by hovering it
script.on_event(defines.events.on_selected_entity_changed, function(event)
    if not logic.is_linking(event.player_index) then return end
    local player = game.get_player(event.player_index)
    local data = logic.try_link(event.player_index, player and player.selected)
    if data then gui.notify_linked(player, data) end
end)

script.on_event(defines.events.on_entity_settings_pasted, function(event)
    local source, destination = event.source, event.destination
    if not (logic.is_cannon(source) and logic.is_cannon(destination)) then return end
    local data = logic.copy_settings(source, destination)
    local player = game.get_player(event.player_index)
    if player then gui.notify_pasted(player, data) end
end)

-- Main loop -------------------------------------------------------------------
script.on_nth_tick(logic.CHECK_INTERVAL, function()
    logic.update_all()
    gui.refresh_opened()
end)
