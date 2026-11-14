-- Everything the player sees. Reads and changes state only through scripts/logic.lua.
local logic = require("scripts.logic")

local gui = {}
local FRAME_NAME = "se_smart_cannon_frame"

-- Localised string helper: locale/<lang>/config.cfg, category [se-smart-cannon]
local function L(key, ...) return {"se-smart-cannon." .. key, ...} end

local GREEN, RED = {r = 0.2, g = 0.8, b = 0.2}, {r = 0.9, g = 0.2, b = 0.2}

-- Chat messages respect the per-player setting "se-sc-show-messages"
local function say(player, message)
    if settings.get_player_settings(player)["se-sc-show-messages"].value then
        player.print(message)
    end
end

function gui.target_text(data)
    local t = data.target
    if not t then return L("target-none") end
    local surface = game.get_surface(t.surface_index)
    return L("target-format", surface and surface.name or "?",
        math.floor(t.position.x), math.floor(t.position.y))
end

-- Build / destroy ---------------------------------------------------------------
function gui.destroy(player)
    local frame = player.gui.relative[FRAME_NAME]
    if frame then frame.destroy() end
    if storage.sc_gui then storage.sc_gui[player.index] = nil end
end

function gui.build(player, cannon)
    gui.destroy(player)
    local data = logic.get(cannon)
    local refs = {}

    refs.frame = player.gui.relative.add{
        type = "frame", name = FRAME_NAME, caption = L("title"), direction = "vertical",
        anchor = {gui = defines.relative_gui_type.assembling_machine_gui,
                  position = defines.relative_gui_position.right},
    }
    local inner = refs.frame.add{type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"}

    -- Mode buttons: Manual | Auto | Multi-Auto (soon)
    inner.add{type = "label", caption = L("mode-title"), style = "caption_label"}
    local modes = inner.add{type = "flow", direction = "horizontal"}
    refs.mode_manual = modes.add{type = "button", name = "se_sc_mode_manual", caption = L("mode-manual")}
    refs.mode_auto   = modes.add{type = "button", name = "se_sc_mode_auto",   caption = L("mode-auto")}
    refs.mode_multi  = modes.add{type = "button", name = "se_sc_mode_multi",
        caption = L("mode-multi"), tooltip = L("mode-multi-tooltip"), enabled = false}

    -- Target (captured from the cannon)
    inner.add{type = "line"}
    inner.add{type = "label", caption = L("target-title"), style = "caption_label"}
    local tflow = inner.add{type = "flow", direction = "horizontal"}
    tflow.style.vertical_align = "center"
    refs.target_label = tflow.add{type = "label"}
    refs.target_label.style.minimal_width = 160
    if not logic.targeter_hooked then   -- fallback only
        tflow.add{type = "button", name = "se_sc_link_chest", caption = L("link-chest"), style = "tool_button"}
    end

    -- Stop limit
    inner.add{type = "line"}
    inner.add{type = "label", caption = L("limit-title"), style = "caption_label", tooltip = L("limit-tooltip")}
    refs.slider = inner.add{type = "slider", name = "se_sc_limit_slider",
        minimum_value = 1, maximum_value = math.max(data.limit, 48),
        value = data.limit, value_step = 1, discrete_slider = true}
    refs.slider.style.horizontally_stretchable = true

    -- Capacity and status
    inner.add{type = "line"}
    inner.add{type = "label", caption = L("capacity-title")}
    refs.bar = inner.add{type = "progressbar", value = 0}
    refs.bar.style.horizontally_stretchable = true
    refs.slots_label  = inner.add{type = "label"}
    refs.status_label = inner.add{type = "label", style = "bold_label"}

    storage.sc_gui = storage.sc_gui or {}
    storage.sc_gui[player.index] = refs
    gui.refresh(player, data)
end

-- Refresh (cheap: only touches stored element references) -------------------------
local function set_style(button, wanted)
    if button.style.name ~= wanted then button.style = wanted end
end

function gui.refresh(player, data)
    local refs = storage.sc_gui and storage.sc_gui[player.index]
    if not (refs and refs.frame.valid) then return end

    local used, total = logic.chest_usage(data)
    used = used or 0
    local limit = math.max(data.limit, 1)

    set_style(refs.mode_manual, data.mode == logic.MODE_MANUAL and "green_button" or "button")
    set_style(refs.mode_auto,   data.mode == logic.MODE_AUTO   and "green_button" or "button")

    refs.target_label.caption = gui.target_text(data)

    local max = math.max(total or 48, data.limit)
    if refs.slider.get_slider_maximum() ~= max then refs.slider.set_slider_minimum_maximum(1, max) end
    if refs.slider.slider_value ~= data.limit then refs.slider.slider_value = data.limit end

    refs.slots_label.caption  = L("slots", used, data.limit)
    refs.status_label.caption = L("status-" .. logic.status(data))
    refs.bar.value = math.min(used / limit, 1)
    refs.bar.style.color = (used >= limit) and RED or GREEN
end

function gui.refresh_opened()
    if not (storage.sc_gui and next(storage.sc_gui)) then return end
    for player_index in pairs(storage.sc_gui) do
        local player = game.get_player(player_index)
        local cannon = logic.get_opened(player_index)
        if player and cannon then gui.refresh(player, logic.get(cannon)) end
    end
end

-- Messages ------------------------------------------------------------------------
function gui.notify_target_set(player, data)
    say(player, L("msg-target-set", gui.target_text(data)))
end

function gui.notify_linked(player, data)
    say(player, L("msg-linked"))
    gui.refresh(player, data)
end

function gui.notify_pasted(player, data)
    say(player, L("msg-settings-pasted", gui.target_text(data)))
end

-- Event handlers (registered in control.lua) -------------------------------------
local CLICK = {
    se_sc_mode_manual = function(player, data)
        logic.set_mode(data, logic.MODE_MANUAL)
        gui.refresh(player, data)
    end,
    se_sc_mode_auto = function(player, data)
        logic.set_mode(data, logic.MODE_AUTO)
        gui.refresh(player, data)
    end,
    se_sc_link_chest = function(player, data)
        logic.begin_link(player.index, data)
        player.print(L("msg-link-prompt", logic.CHEST_NAME))   -- instruction: always shown
    end,
    -- se_sc_mode_multi: coming soon, the button is disabled for now
}

function gui.on_opened(event)
    local entity = event.entity
    if not logic.is_cannon(entity) then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    logic.set_opened(event.player_index, entity)
    gui.build(player, entity)
end

function gui.on_closed(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    -- keep the "last opened cannon": the player aims from remote view after closing the GUI
    logic.cancel_link(event.player_index)
    gui.destroy(player)
end

function gui.on_click(event)
    local element = event.element
    if not (element and element.valid) then return end
    local handler = CLICK[element.name]
    if not handler then return end
    local cannon = logic.get_opened(event.player_index)
    local player = game.get_player(event.player_index)
    if cannon and player then handler(player, logic.get(cannon)) end
end

function gui.on_value_changed(event)
    local element = event.element
    if not (element and element.valid and element.name == "se_sc_limit_slider") then return end
    local cannon = logic.get_opened(event.player_index)
    local player = game.get_player(event.player_index)
    if not (cannon and player) then return end
    local data = logic.get(cannon)
    logic.set_limit(data, element.slider_value)
    gui.refresh(player, data)
end

return gui