-- Game logic only. No GUI code in this file.
local logic = {}

logic.CANNON_NAMES = {
    ["se-delivery-cannon"]        = true,
    ["se-delivery-cannon-weapon"] = true,
}
logic.CHEST_NAME      = "se-delivery-cannon-chest"
logic.CHECK_INTERVAL  = settings.startup["se-sc-check-interval"].value
logic.MODE_MANUAL     = "manual"
logic.MODE_AUTO       = "auto"
logic.MODE_MULTI      = "multi-auto"   -- soon, not used yet
logic.targeter_hooked = false          -- set from control.lua

local TARGETER_ITEM = "se-delivery-cannon-targeter"
local SCHEMA        = 3

-- Settings (read at call time so runtime-global changes apply immediately) -------
local function default_limit()      return settings.global["se-sc-default-limit"].value end
local function default_mode()       return settings.global["se-sc-default-mode"].value end
local function stop_without_chest() return settings.global["se-sc-stop-without-chest"].value end

-- Storage / migration ----------------------------------------------------------
local function migrate_cannon(data)
    local cannon = data.entity
    if not (cannon and cannon.valid) then return end

    -- v1 stopped cannons through the energy interface: give the buffer back
    if data.saved_buffer then
        local iface = cannon.surface.find_entity(cannon.name .. "-energy-interface", cannon.position)
        if iface then iface.electric_buffer_size = data.saved_buffer end
        data.saved_buffer = nil
    end
    -- v2 linked a chest by hand: its position becomes the target
    if data.chest and data.chest.valid and not data.target then
        data.target = {
            surface_index = data.chest.surface.index,
            position = {x = data.chest.position.x, y = data.chest.position.y},
        }
    end
    data.mode    = data.mode or logic.MODE_MANUAL
    data.limit   = tonumber(data.limit) or default_limit()
    data.stopped = data.stopped or false
end

local function ensure()
    if storage.sc_schema == SCHEMA then return end
    storage.smart_cannons_v2 = storage.smart_cannons_v2 or {}
    storage.sc_linking = storage.sc_linking or {}
    storage.sc_opened  = storage.sc_opened  or {}
    for _, data in pairs(storage.smart_cannons_v2) do migrate_cannon(data) end
    storage.cannons, storage.smart_cannons = nil, nil
    storage.linking, storage.opened, storage.last_opened = nil, nil, nil
    storage.sc_schema = SCHEMA
end
logic.ensure = ensure

function logic.is_cannon(entity)
    return entity ~= nil and entity.valid and logic.CANNON_NAMES[entity.name] == true
end

function logic.get(cannon)
    ensure()
    local all = storage.smart_cannons_v2
    local data = all[cannon.unit_number]
    if not data then
        data = {entity = cannon, mode = default_mode(), limit = default_limit(), stopped = false}
        all[cannon.unit_number] = data
    end
    data.entity = cannon
    return data
end

-- Last cannon GUI opened by a player (needed when aiming from remote view) -----
function logic.set_opened(player_index, cannon)
    ensure()
    storage.sc_opened[player_index] = cannon
end

function logic.get_opened(player_index)
    ensure()
    local cannon = storage.sc_opened[player_index]
    if cannon and cannon.valid then return cannon end
end

-- Target and chest --------------------------------------------------------------
-- The chest is located exactly like Space Exploration does when a capsule lands.
function logic.get_chest(data)
    if data.chest and data.chest.valid then return data.chest end
    local t = data.target
    if not t then return nil end
    local surface = game.get_surface(t.surface_index)
    if not surface then return nil end
    data.chest = surface.find_entities_filtered{name = logic.CHEST_NAME, position = t.position, limit = 1}[1]
    return data.chest
end

-- Returns used_slots, total_slots (nil if there is no chest).
function logic.chest_usage(data)
    local chest = logic.get_chest(data)
    local inv = chest and chest.get_inventory(defines.inventory.chest)
    if not inv then return nil end
    local total = #inv
    return total - inv.count_empty_stacks(), total
end

-- Stopping / resuming ------------------------------------------------------------
-- Space Exploration fires a cannon only if there is a capsule in its output.
-- Stop = disable crafting (no new capsules) + park the ready capsule in a script inventory.
local function output_inventory(cannon)
    return cannon.get_inventory(defines.inventory.crafter_output)
end

local function stash_output(data)
    local out = output_inventory(data.entity)
    if not out then return end
    for i = 1, #out do
        if out[i].valid_for_read then
            data.stash = data.stash or game.create_inventory(#out)
            if i <= #data.stash and not data.stash[i].valid_for_read then
                data.stash[i].transfer_stack(out[i])
            end
        end
    end
end

local function restore_stash(data)
    local stash = data.stash
    if not stash then return end
    local out = output_inventory(data.entity)
    if out then
        for i = 1, #stash do
            if stash[i].valid_for_read and i <= #out then
                out[i].transfer_stack(stash[i])
            end
        end
    end
    if stash.is_empty() then
        stash.destroy()
        data.stash = nil
    end
end

local function stop_cannon(data)
    if not data.entity.disabled_by_script then data.entity.disabled_by_script = true end
    data.stopped = true
    stash_output(data)
end

local function resume_cannon(data)
    if data.stopped then
        data.entity.disabled_by_script = false
        data.stopped = false
    end
    restore_stash(data)   -- retried every loop tick until the slot is free
end

local function should_stop(data)
    if data.mode ~= logic.MODE_AUTO then return false end
    -- no target / no chest at the target: stop only if the setting says so
    if not data.target then return stop_without_chest() end
    local used = logic.chest_usage(data)
    if used == nil then return stop_without_chest() end
    return used >= data.limit
end

function logic.update(data)
    if should_stop(data) then stop_cannon(data) else resume_cannon(data) end
end

function logic.update_all()
    ensure()
    for unit_number, data in pairs(storage.smart_cannons_v2) do
        if data.entity and data.entity.valid then
            logic.update(data)
        else
            if data.stash then data.stash.destroy() end
            storage.smart_cannons_v2[unit_number] = nil
        end
    end
end

-- Status code, translated by the GUI:
-- manual | no-target | no-chest | no-chest-firing | full | ready
function logic.status(data)
    if data.mode == logic.MODE_MANUAL then return "manual" end
    local used = data.target and logic.chest_usage(data)
    if not used then
        if not stop_without_chest() then return "no-chest-firing" end
        return data.target and "no-chest" or "no-target"
    end
    if used >= data.limit then return "full" end
    return "ready"
end

-- Setters used by the GUI -----------------------------------------------------
function logic.set_mode(data, mode)
    data.mode = mode
    logic.update(data)
end

function logic.set_limit(data, limit)
    data.limit = math.max(1, math.floor(limit))
    logic.update(data)
end

function logic.set_target(data, surface_index, position)
    data.target = {surface_index = surface_index, position = {x = position.x, y = position.y}}
    data.chest = nil
    logic.update(data)
end

-- Target capture ---------------------------------------------------------------
function logic.find_targeter_inputs()
    local names = {}
    for name in pairs(prototypes.custom_input) do
        if string.find(name, "targeter", 1, true) then names[#names + 1] = name end
    end
    return names
end

-- Called on the SE targeter input; returns the cannon data if a target was captured.
function logic.capture_target(player, position)
    local cursor = player.cursor_stack
    if not (cursor and cursor.valid_for_read and cursor.name == TARGETER_ITEM) then return nil end
    local cannon = logic.get_opened(player.index)
    if not cannon then return nil end
    local data = logic.get(cannon)
    logic.set_target(data, player.surface.index, position)
    return data
end

-- Fallback: link by hovering a chest ---------------------------------------------
function logic.begin_link(player_index, data)
    ensure()
    storage.sc_linking[player_index] = data.entity
end

function logic.cancel_link(player_index)
    ensure()
    storage.sc_linking[player_index] = nil
end

function logic.is_linking(player_index)
    ensure()
    return storage.sc_linking[player_index] ~= nil
end

function logic.try_link(player_index, selected)
    ensure()
    local cannon = storage.sc_linking[player_index]
    if not cannon then return nil end
    if not cannon.valid then storage.sc_linking[player_index] = nil return nil end
    if not (selected and selected.valid and selected.name == logic.CHEST_NAME) then return nil end
    local data = logic.get(cannon)
    logic.set_target(data, selected.surface.index, selected.position)
    storage.sc_linking[player_index] = nil
    return data
end
-- Copy/paste settings between two cannons: mode, limit and target are copied together,
-- the same way Space Exploration copies its own mode and destination.
function logic.copy_settings(source, destination)
    local from = logic.get(source)
    local to   = logic.get(destination)

    to.mode  = from.mode
    to.limit = from.limit
    if from.target then
        to.target = {
            surface_index = from.target.surface_index,
            position = {x = from.target.position.x, y = from.target.position.y},
        }
    else
        to.target = nil
    end
    to.chest = nil          -- will be looked up again at the new target
    logic.update(to)        -- applies stop/resume immediately
    return to
end
-- Removal ---------------------------------------------------------------------
function logic.on_removed(event)
    local entity = event.entity
    if not logic.is_cannon(entity) then return end
    ensure()
    local data = storage.smart_cannons_v2[entity.unit_number]
    if data then
        if data.stash then   -- never lose parked capsules
            entity.surface.spill_inventory{position = entity.position, inventory = data.stash}
            data.stash.destroy()
            data.stash = nil
        end
        storage.smart_cannons_v2[entity.unit_number] = nil
    end
end

return logic

