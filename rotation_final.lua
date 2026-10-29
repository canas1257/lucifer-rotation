-- rotation_final.lua
-- Kolaborasi: Anna & Salsa | Target: Lucifer v2.86
-- ponytail: single-table config, zero extra dependencies, self-contained state machine with white door warp recovery

local CONFIG = {
    FARMS = {
        { world = "FARM1", door = "" },
        { world = "FARM2", door = "" },
    },
    HOME = { world = "MYHOME", door = "" },
    STORAGE = { world = "MYSTORE", door = "" },

    BLOCK_ID = 4584,
    SEED_ID = 4585,

    BATCH_LIMIT = 20,
    STORE_SEED_MIN = 100,
    PUNCH_RETRY_MAX = 15,

    ACTION_INTERVALS = {
        hit = 0.18,
        place = 0.16,
        move = 0.20,
    }
}

local bot = getBot()
if not bot then return end

bot.leave_world_before_warp = false
bot:setInterval(Action.hit, CONFIG.ACTION_INTERVALS.hit)
bot:setInterval(Action.place, CONFIG.ACTION_INTERVALS.place)
bot:setInterval(Action.move, CONFIG.ACTION_INTERVALS.move)

local STATE = {
    HARVEST = 1,
    BREAK_HOME = 2,
    PLANT = 3,
    STORE = 4,
    NEXT_WORLD = 5,
}

local function waitOnline(timeout)
    for _ = 1, (timeout or 30) do
        if bot.status == BotStatus.online then return true end
        sleep(1000)
    end
    return false
end

-- Deteksi apakah bot berada pada tile White Door (ID 6)
local function isAtWhiteDoor()
    local world = bot:getWorld()
    if not world then return false end
    local tile = world:getTile(bot.x, bot.y)
    return tile ~= nil and tile.fg == 6
end

local function warp(dest)
    local world = type(dest) == "table" and dest.world or dest
    local door = type(dest) == "table" and (dest.door or "") or ""

    if not waitOnline() then return false end
    if bot:isInWorld(world) and bot:isInWorld() then
        if isAtWhiteDoor() and door ~= "" then
            bot:warp(world, door)
            sleep(1000)
        end
        return true
    end

    bot:warp(world, door)
    for _ = 1, 30 do
        sleep(1000)
        if bot:isInWorld(world) and bot:isInWorld() then
            sleep(800)
            if isAtWhiteDoor() and door ~= "" then
                bot:warp(world, door)
                sleep(1000)
            end
            return true
        end
        if not waitOnline(5) then return false end
    end
    return false
end

local function recoverIfAtWhiteDoor(dest)
    if isAtWhiteDoor() then
        local world = type(dest) == "table" and dest.world or dest
        local door = type(dest) == "table" and (dest.door or "") or ""
        print("[Alert] Terdeteksi di White Door (ID 6), re-warp ke: " .. world .. "|" .. door)
        bot:warp(world, door)
        sleep(1000)
    end
end

local function doHarvest(dest)
    if not warp(dest) then return STATE.NEXT_WORLD end

    local world = bot:getWorld()
    if not world then return STATE.HARVEST end

    local harvested = 0
    for _, tile in ipairs(world:getTilesSafe()) do
        if not waitOnline() then return STATE.HARVEST end
        recoverIfAtWhiteDoor(dest)

        if bot:getInventory().emptyslots <= 1 or harvested >= CONFIG.BATCH_LIMIT then
            return STATE.BREAK_HOME
        end

        if tile:canHarvest() and bot:findPath(tile.x, tile.y) then
            bot:hit(tile.x, tile.y)
            sleep(180)
            bot:collect(3)
            harvested = harvested + 1
        end
    end

    return harvested > 0 and STATE.BREAK_HOME or STATE.NEXT_WORLD
end

local function doBreakHome()
    local blocks = bot:getInventory():findItem(CONFIG.BLOCK_ID)
    if blocks == 0 then return STATE.PLANT end
    if not warp(CONFIG.HOME) then return STATE.BREAK_HOME end

    local bx, by = bot.x + 1, bot.y
    while waitOnline() and bot:getInventory():findItem(CONFIG.BLOCK_ID) > 0 do
        if isAtWhiteDoor() then
            print("[Alert] Respawn ke White Door saat break! Re-warp ke Home...")
            warp(CONFIG.HOME)
            bot:findPath(bx - 1, by)
            sleep(500)
        end

        local world = bot:getWorld()
        if not world then break end

        local target = world:getTile(bx, by)
        if target and target.fg == 0 then
            bot:place(bx, by, CONFIG.BLOCK_ID)
            sleep(160)
        end

        local hits = 0
        while waitOnline() and hits < CONFIG.PUNCH_RETRY_MAX do
            if isAtWhiteDoor() then break end
            local cur = bot:getWorld():getTile(bx, by)
            if not cur or cur.fg == 0 then break end
            bot:hit(bx, by)
            hits = hits + 1
            sleep(180)
        end
        bot:collect(2)
        if hits >= CONFIG.PUNCH_RETRY_MAX then break end
    end

    return STATE.PLANT
end

local function doPlant(dest)
    local seeds = bot:getInventory():findItem(CONFIG.SEED_ID)
    if seeds == 0 then return STATE.STORE end
    if not warp(dest) then return STATE.PLANT end

    local world = bot:getWorld()
    if not world then return STATE.PLANT end

    for _, tile in ipairs(world:getTilesSafe()) do
        if not waitOnline() or bot:getInventory():findItem(CONFIG.SEED_ID) == 0 then break end
        recoverIfAtWhiteDoor(dest)

        if tile.fg ~= 0 and tile.fg ~= 6 and tile.y > 0 then
            local above = world:getTile(tile.x, tile.y - 1)
            if above and above.fg == 0 and bot:findPath(tile.x, tile.y - 1) then
                bot:place(tile.x, tile.y - 1, CONFIG.SEED_ID)
                sleep(160)
            end
        end
    end

    print("[Info] Gems: " .. bot.gem_count)
    return STATE.STORE
end

local function doStore()
    local seeds = bot:getInventory():findItem(CONFIG.SEED_ID)
    if seeds >= CONFIG.STORE_SEED_MIN then
        if warp(CONFIG.STORAGE) then
            bot:fastDrop(CONFIG.SEED_ID, seeds)
            sleep(1000)
        end
    end
    return STATE.HARVEST
end

-- Engine Runner
for _, currentFarm in ipairs(CONFIG.FARMS) do
    local farmName = type(currentFarm) == "table" and currentFarm.world or currentFarm
    print("[Engine] Memulai farm: " .. farmName)
    local currentState = STATE.HARVEST

    while waitOnline() do
        if currentState == STATE.HARVEST then
            currentState = doHarvest(currentFarm)
        elseif currentState == STATE.BREAK_HOME then
            currentState = doBreakHome()
        elseif currentState == STATE.PLANT then
            currentState = doPlant(currentFarm)
        elseif currentState == STATE.STORE then
            currentState = doStore()
        elseif currentState == STATE.NEXT_WORLD then
            break
        end
    end
end

print("[Selesai] Seluruh farm rotasi selesai diproses.")
