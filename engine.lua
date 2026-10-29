-- engine.lua
-- Core Rotation State Machine with Webhook Live Monitor & Auto Buy Pack
-- Target: Lucifer v2.86 | https://github.com/canas1257/lucifer-rotation
-- Dipanggil otomatis oleh loader.lua

local CONFIG = ... or _G.CONFIG
if not CONFIG then
    print("[Error] CONFIG tidak ditemukan. Harap jalankan script melalui loader.lua")
    return
end

local bot = getBot()
if not bot then
    print("[Error] Bot context tidak ditemukan. Script harus dijalankan di Lucifer bot.")
    return
end

-- ========================================================
-- INISIALISASI & INTERVALS
-- ========================================================
bot.leave_world_before_warp = true

local intervals = CONFIG.ACTION_INTERVALS or {}
bot:setInterval(Action.hit, intervals.hit or 0.18)
bot:setInterval(Action.place, intervals.place or 0.16)
bot:setInterval(Action.move, intervals.move or 0.20)

local STATE = {
    HARVEST = 1,
    BREAK_HOME = 2,
    PLANT = 3,
    BUY_PACK = 4,
    STORE = 5,
    NEXT_WORLD = 6,
}

-- ========================================================
-- WEBHOOK MONITORING (LIVE DASHBOARD)
-- ========================================================
local webhookClient = nil
if CONFIG.WEBHOOK and CONFIG.WEBHOOK.ENABLED and CONFIG.WEBHOOK.URL and CONFIG.WEBHOOK.URL ~= "" then
    webhookClient = Webhook.new(CONFIG.WEBHOOK.URL)
    if CONFIG.WEBHOOK.MESSAGE_ID and CONFIG.WEBHOOK.MESSAGE_ID ~= "" then
        webhookClient.message_id = tostring(CONFIG.WEBHOOK.MESSAGE_ID)
    end
end

local function updateWebhook(activity, currentFarm)
    if not webhookClient then return end

    local worldName = bot:isInWorld() and bot:getWorld().name or "In Transit"
    local inv = bot:getInventory()
    local emptySlots = inv and inv.emptyslots or 0
    local totalSlots = inv and inv.slotcount or 0
    local ping = bot.getPing and bot:getPing() or 0
    local uptime = bot.getActiveTime and bot:getActiveTime() or "-"
    local isOnline = (bot.status == BotStatus.online)

    webhookClient.embed1.use = true
    webhookClient.embed1.title = "🤖 Bot Status Monitor — " .. (bot.name or "Lucifer Bot")
    webhookClient.embed1.color = isOnline and 3066993 or 15158332
    webhookClient.embed1.description = "Live monitor status aktivitas bot & auto buy pack"

    webhookClient.embed1:addField("Status Bot", isOnline and "🟢 Online" or "🔴 Offline (" .. tostring(bot.status) .. ")", true)
    webhookClient.embed1:addField("World Sekarang", "🗺️ `" .. worldName .. "`", true)
    webhookClient.embed1:addField("Target Farm", "🌾 `" .. tostring(currentFarm or "-") .. "`", true)

    webhookClient.embed1:addField("Aktivitas", "⚙️ " .. tostring(activity or "Idle"), false)

    webhookClient.embed1:addField("Gems", "💎 " .. tostring(bot.gem_count or 0), true)
    webhookClient.embed1:addField("Tas (Slot)", "🎒 " .. tostring(emptySlots) .. " / " .. tostring(totalSlots) .. " kosong", true)
    webhookClient.embed1:addField("Ping", "📶 " .. tostring(ping) .. " ms", true)
    webhookClient.embed1:addField("Waktu Aktif", "⏱️ " .. tostring(uptime), true)

    if CONFIG.AUTO_BUY_PACK and CONFIG.AUTO_BUY_PACK.ENABLED and CONFIG.AUTO_BUY_PACK.ItemIDOfPack then
        local packItemsInfo = {}
        for _, id in ipairs(CONFIG.AUTO_BUY_PACK.ItemIDOfPack) do
            local cnt = inv and inv:findItem(id) or 0
            local info = getInfo(id)
            local name = info and info.name or ("ID " .. tostring(id))
            table.insert(packItemsInfo, string.format("%s: %d", name, cnt))
        end
        if #packItemsInfo > 0 then
            webhookClient.embed1:addField("Item Pack (di Tas)", "📦 " .. table.concat(packItemsInfo, ", "), false)
        end
    end

    if webhookClient.message_id and webhookClient.message_id ~= "" then
        webhookClient:edit()
    else
        webhookClient:send()
    end
end

-- ========================================================
-- HELPER FUNCTIONS & PROTEKSI
-- ========================================================
local function waitOnline(timeout)
    for _ = 1, (timeout or 30) do
        if bot.status == BotStatus.online then return true end
        sleep(1000)
    end
    return false
end

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
        if door ~= "" then
            bot:warp(world, door)
            sleep(1000)
        end
    end
end

-- ========================================================
-- STATE HANDLERS
-- ========================================================
local function doHarvest(dest)
    local farmName = type(dest) == "table" and dest.world or dest
    updateWebhook("Memanen Pohon (Harvest)", farmName)

    if not warp(dest) then return STATE.NEXT_WORLD end

    local world = bot:getWorld()
    if not world then return STATE.HARVEST end

    local harvested = 0
    for _, tile in ipairs(world:getTilesSafe()) do
        if not waitOnline() then return STATE.HARVEST end
        recoverIfAtWhiteDoor(dest)

        if bot:getInventory().emptyslots <= 1 or harvested >= (CONFIG.BATCH_LIMIT or 20) then
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

local function doBreakHome(dest)
    local farmName = type(dest) == "table" and dest.world or dest
    local blocks = bot:getInventory():findItem(CONFIG.BLOCK_ID)
    if blocks == 0 then return STATE.PLANT end

    updateWebhook("Memecahkan Blok di Home", farmName)
    if not warp(CONFIG.HOME) then return STATE.BREAK_HOME end

    local bx, by = bot.x + 1, bot.y
    local maxHits = CONFIG.PUNCH_RETRY_MAX or 15

    while waitOnline() and bot:getInventory():findItem(CONFIG.BLOCK_ID) > 0 do
        if isAtWhiteDoor() then
            print("[Alert] Respawn ke White Door saat break! Kembali ke posisi kerja...")
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
        while waitOnline() and hits < maxHits do
            if isAtWhiteDoor() then break end
            local cur = bot:getWorld():getTile(bx, by)
            if not cur or cur.fg == 0 then break end
            bot:hit(bx, by)
            hits = hits + 1
            sleep(180)
        end
        bot:collect(2)
        if hits >= maxHits then break end
    end

    return STATE.PLANT
end

local function doPlant(dest)
    local farmName = type(dest) == "table" and dest.world or dest
    local seeds = bot:getInventory():findItem(CONFIG.SEED_ID)
    if seeds == 0 then return STATE.BUY_PACK end

    updateWebhook("Menanam Kembali Seed (Plant)", farmName)
    if not warp(dest) then return STATE.PLANT end

    local world = bot:getWorld()
    if not world then return STATE.PLANT end

    for _, tile in ipairs(world:getTilesSafe()) do
        if not waitOnline() or bot:getInventory():findItem(CONFIG.SEED_ID) == 0 then break end
        recoverIfAtWhiteDoor(dest)

        if tile.fg == 0 and tile.bg ~= 0 and bot:findPath(tile.x, tile.y) then
            bot:place(tile.x, tile.y, CONFIG.SEED_ID)
            sleep(160)
        end
    end

    print("[Info] Gems saat ini: " .. bot.gem_count)
    return STATE.BUY_PACK
end

local function doBuyPack(dest)
    local farmName = type(dest) == "table" and dest.world or dest
    local packCfg = CONFIG.AUTO_BUY_PACK

    if packCfg and packCfg.ENABLED and packCfg.PricePack and packCfg.PackName then
        local price = packCfg.PricePack
        if bot.gem_count >= price then
            updateWebhook("Membeli Pack di Store: " .. packCfg.PackName, farmName)
            print(string.format("[AutoBuy] Memulai beli pack '%s' (Gems: %d | Harga: %d)", packCfg.PackName, bot.gem_count, price))

            local delayBuy = packCfg.DelayBuyPack or 1500
            while waitOnline() and bot.gem_count >= price do
                bot:buy(packCfg.PackName)
                sleep(delayBuy)
            end
            print("[AutoBuy] Selesai beli pack. Sisa gems: " .. bot.gem_count)
        end
    end

    return STATE.STORE
end

local function doStore(dest)
    local farmName = type(dest) == "table" and dest.world or dest
    local minSeed = CONFIG.STORE_SEED_MIN or 100
    local seeds = bot:getInventory():findItem(CONFIG.SEED_ID)

    local packCfg = CONFIG.AUTO_BUY_PACK
    local hasPackItems = false
    if packCfg and packCfg.ENABLED and packCfg.ItemIDOfPack then
        local inv = bot:getInventory()
        for _, id in ipairs(packCfg.ItemIDOfPack) do
            if inv and inv:findItem(id) > 0 then
                hasPackItems = true
                break
            end
        end
    end

    if seeds >= minSeed or hasPackItems then
        updateWebhook("Menyimpan Seed & Drop Item Pack ke Storage", farmName)
        if warp(CONFIG.STORAGE) then
            -- 1. Drop Seed
            if seeds >= minSeed then
                print(string.format("[Storage] Menyimpan %d seed ke storage...", seeds))
                bot:fastDrop(CONFIG.SEED_ID, seeds)
                sleep(1000)
            end

            -- 2. Drop Item Hasil Beli Pack
            if hasPackItems and packCfg then
                if packCfg.DropPlacement then
                    local dx, dy
                    if type(packCfg.DropPlacement) == "table" then
                        dx, dy = packCfg.DropPlacement.x, packCfg.DropPlacement.y
                    elseif type(packCfg.DropPlacement) == "number" and packCfg.DropPlacement > 100 then
                        dx = packCfg.DropPlacement % 100
                        dy = math.floor(packCfg.DropPlacement / 100)
                    end

                    if dx and dy and bot:getWorld():isValidTile(dx, dy) then
                        print(string.format("[Storage] Menuju lokasi DropPlacement (%d, %d)...", dx, dy))
                        bot:findPath(dx, dy)
                        sleep(packCfg.DelayDrop or 2000)
                    end
                end

                local delayFPDrop = packCfg.DelayFPDrop or 1000
                for _, itemId in ipairs(packCfg.ItemIDOfPack) do
                    local count = bot:getInventory():findItem(itemId)
                    if count > 0 then
                        print(string.format("[Storage] Menjatuhkan %d unit item [ID %d]...", count, itemId))
                        bot:fastDrop(itemId, count)
                        sleep(delayFPDrop)
                    end
                end
            end
        end
    end

    return STATE.HARVEST
end

-- ========================================================
-- ENGINE EXECUTION
-- ========================================================
print("[Engine] Memulai eksekusi rotasi Lucifer v2.86...")
updateWebhook("Engine Dimulai", "-")

for _, currentFarm in ipairs(CONFIG.FARMS) do
    local farmName = type(currentFarm) == "table" and currentFarm.world or currentFarm
    print("[Engine] Memulai farm: " .. farmName)
    local currentState = STATE.HARVEST

    while waitOnline() do
        if currentState == STATE.HARVEST then
            currentState = doHarvest(currentFarm)
        elseif currentState == STATE.BREAK_HOME then
            currentState = doBreakHome(currentFarm)
        elseif currentState == STATE.PLANT then
            currentState = doPlant(currentFarm)
        elseif currentState == STATE.BUY_PACK then
            currentState = doBuyPack(currentFarm)
        elseif currentState == STATE.STORE then
            currentState = doStore(currentFarm)
        elseif currentState == STATE.NEXT_WORLD then
            break
        end
    end
end

updateWebhook("Seluruh Farm Rotasi Selesai", "-")
print("[Engine] Seluruh farm dalam rotasi selesai diproses.")
