-- engine.lua
-- Core Rotation State Machine for Lucifer v2.86
-- https://github.com/canas1257/lucifer-rotation
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
-- DISCORD WEBHOOK MONITORING (EDIT PESAN REALTIME)
-- ========================================================
local webhookClient = nil
local lastWebhookSent = 0

local function updateWebhook(currentAction, activeFarm)
    local cfg = CONFIG.WEBHOOK
    if not cfg or not cfg.ENABLED or not cfg.URL or cfg.URL == "" or cfg.URL:find("MASUKKAN_URL") then
        return
    end

    local now = os.time and os.time() or 0
    if (now - lastWebhookSent) < 3 then return end
    lastWebhookSent = now

    if not webhookClient then
        webhookClient = Webhook.new(cfg.URL)
        webhookClient.username = "Lucifer Monitor (" .. tostring(bot.name) .. ")"
    end

    if cfg.MESSAGE_ID and cfg.MESSAGE_ID ~= "" then
        webhookClient.message_id = tostring(cfg.MESSAGE_ID)
    end

    local isOnline = (bot.status == BotStatus.online)
    local currentWorld = (bot:isInWorld() and bot:getWorld().name or "In Transit")
    local tilePos = string.format("(%d, %d)", bot.x or 0, bot.y or 0)
    local ping = tostring(bot:getPing()) .. " ms"
    local gems = tostring(bot.gem_count or 0)

    local inv = bot:getInventory()
    local slots = inv and (tostring(inv.itemcount) .. "/" .. tostring(inv.slotcount)) or "-"
    local emptySlots = inv and tostring(inv.emptyslots) or "-"

    local packItemStr = "-"
    local packCfg = CONFIG.AUTO_BUY_PACK
    if packCfg and packCfg.ENABLED and packCfg.ItemIDOfPack and inv then
        local parts = {}
        for _, id in ipairs(packCfg.ItemIDOfPack) do
            local c = inv:findItem(id)
            if c > 0 then table.insert(parts, string.format("ID %d: %d", id, c)) end
        end
        if #parts > 0 then packItemStr = table.concat(parts, ", ") end
    end

    local statusColor = isOnline and 3066993 or 15158332

    webhookClient.content = ""
    webhookClient.embed1.use = true
    webhookClient.embed1.color = statusColor
    webhookClient.embed1.title = "📊 Lucifer Rotation v2.86 — " .. tostring(bot.name)
    webhookClient.embed1.description = string.format("**Aktivitas:** %s\n**Target Farm:** %s", tostring(currentAction or "-"), tostring(activeFarm or "-"))

    webhookClient.embed1:addField("Status", isOnline and "🟢 ONLINE" or "🔴 OFFLINE", true)
    webhookClient.embed1:addField("World Sekarang", currentWorld, true)
    webhookClient.embed1:addField("Posisi Tile", tilePos, true)
    webhookClient.embed1:addField("Gems", gems, true)
    webhookClient.embed1:addField("Ping", ping, true)
    webhookClient.embed1:addField("Slot Tas (Isi/Kosong)", string.format("%s (Sisa %s)", slots, emptySlots), true)
    webhookClient.embed1:addField("Item Pack di Tas", packItemStr, false)

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
-- SMART DROP: Auto geser kanan jika tile penuh (max 20 objek / 4000 item)
-- ========================================================
local function smartDrop(itemId, count, startX, startY, delayDrop)
    local curX = startX or bot.x
    local curY = startY or bot.y
    local world = bot:getWorld()
    local maxWorldX = world and (world.x - 2) or 98
    local delayFPDrop = delayDrop or 1000

    while waitOnline() do
        local inv = bot:getInventory()
        local before = inv:findItem(itemId)
        if before == 0 or count <= 0 then break end

        local toDrop = math.min(count, before)

        if not bot:isInTile(curX, curY) then
            bot:findPath(curX, curY)
            sleep(400)
        end

        bot:fastDrop(itemId, toDrop)
        sleep(delayFPDrop)

        local after = bot:getInventory():findItem(itemId)
        if after < before then
            local dropped = before - after
            count = count - dropped
            print(string.format("[Storage] Sukses drop %d unit item [ID %d] di (%d, %d). Sisa perlu drop: %d", dropped, itemId, curX, curY, count))
            if count <= 0 or after == 0 then
                break
            end
        else
            -- Drop gagal atau tile sudah penuh (mencapai batas 20 floating objects / 4000 item)
            print(string.format("[Storage] Tile (%d, %d) penuh/gagal drop! Geser 1 tile ke kanan...", curX, curY))
            curX = curX + 1
            if curX > maxWorldX then
                print("[Storage] Peringatan: Mencapai batas kanan world saat drop!")
                break
            end
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

        local inv = bot:getInventory()
        -- Aturan Growtopia: Kapasitas per item max 200. Jika blok >= 190, wajib pulang ke home untuk break
        if inv:findItem(CONFIG.BLOCK_ID) >= 190 or inv.emptyslots <= 1 then
            return STATE.BREAK_HOME
        end

        -- Jika seed > 190, drop 100 ke storage dan sisakan sisanya untuk plant
        if inv:findItem(CONFIG.SEED_ID) > 190 then
            return STATE.STORE
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

-- Mencari spot kosong untuk berdiri dan memecahkan blok di Home World
local function findBreakSpot()
    local world = bot:getWorld()
    if not world then return bot.x, bot.y, bot.x + 1, bot.y end

    for _, tile in ipairs(world:getTilesSafe()) do
        local sx, sy = tile.x, tile.y
        if sx >= 2 and sx <= (world.x - 3) and sy >= 2 and sy <= (world.y - 3) then
            if tile.fg == 0 and tile.fg ~= 6 then
                local ground = world:getTile(sx, sy + 1)
                if ground and ground.fg ~= 0 and ground.fg ~= 6 then
                    -- Cek spot break di sisi kanan
                    local rightTile = world:getTile(sx + 1, sy)
                    local rightGround = world:getTile(sx + 1, sy + 1)
                    if rightTile and rightTile.fg == 0 and rightGround and rightGround.fg ~= 0 then
                        if bot:findPath(sx, sy) then
                            return sx, sy, sx + 1, sy
                        end
                    end

                    -- Cek spot break di sisi kiri
                    local leftTile = world:getTile(sx - 1, sy)
                    local leftGround = world:getTile(sx - 1, sy + 1)
                    if leftTile and leftTile.fg == 0 and leftGround and leftGround.fg ~= 0 then
                        if bot:findPath(sx, sy) then
                            return sx, sy, sx - 1, sy
                        end
                    end
                end
            end
        end
    end

    return bot.x, bot.y, bot.x + 1, bot.y
end

local function doBreakHome(dest)
    local farmName = type(dest) == "table" and dest.world or dest
    local blocks = bot:getInventory():findItem(CONFIG.BLOCK_ID)
    if blocks == 0 then return STATE.PLANT end

    updateWebhook("Memecahkan Blok di Home", farmName)
    if not warp(CONFIG.HOME) then return STATE.BREAK_HOME end

    print("[Home] Melakukan auto-scan spot kosong untuk memecah blok...")
    local standX, standY, bx, by = findBreakSpot()
    print(string.format("[Home] Spot terpilih: Berdiri (%d, %d) | Target Break (%d, %d)", standX, standY, bx, by))

    bot:findPath(standX, standY)
    sleep(400)

    local maxHits = CONFIG.PUNCH_RETRY_MAX or 15

    -- Pecahkan sampai habis seluruh blok di tas
    while waitOnline() and bot:getInventory():findItem(CONFIG.BLOCK_ID) > 0 do
        if isAtWhiteDoor() then
            print("[Alert] Respawn ke White Door saat break! Kembali ke posisi kerja...")
            bot:findPath(standX, standY)
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

        -- Jika seed di tas > 190 saat break di home, drop 100 ke storage dan sisakan sebagian untuk plant
        if bot:getInventory():findItem(CONFIG.SEED_ID) > 190 then
            print(string.format("[Home] Seed di tas mencapai %d (> 190). Menyimpan 100 seed ke storage...", bot:getInventory():findItem(CONFIG.SEED_ID)))
            updateWebhook("Menyimpan 100 Seed ke Storage (Tas Penuh)", farmName)
            if warp(CONFIG.STORAGE) then
                smartDrop(CONFIG.SEED_ID, 100, bot.x, bot.y, 1000)
            end
            warp(CONFIG.HOME)
            bot:findPath(standX, standY)
            sleep(400)
        end
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
    local inv = bot:getInventory()
    local seeds = inv:findItem(CONFIG.SEED_ID)
    local packCfg = CONFIG.AUTO_BUY_PACK

    local hasPackItems = false
    if packCfg and packCfg.ENABLED and packCfg.ItemIDOfPack then
        for _, id in ipairs(packCfg.ItemIDOfPack) do
            if inv:findItem(id) > 0 then
                hasPackItems = true
                break
            end
        end
    end

    local seedOver190 = (seeds > 190)
    local needStoreSeed = seedOver190 or (seeds >= (CONFIG.STORE_SEED_MIN or 100))

    if needStoreSeed or hasPackItems then
        updateWebhook("Menyimpan Seed & Drop Item Pack ke Storage", farmName)
        if warp(CONFIG.STORAGE) then
            local sx, sy = bot.x, bot.y

            -- 1. Drop Seed: jika > 190, drop 100 dan sisakan sisanya untuk di-plant
            if needStoreSeed then
                local dropCount = seedOver190 and 100 or seeds
                print(string.format("[Storage] Menyimpan %d seed ke storage (sisa di tas: %d)...", dropCount, seeds - dropCount))
                smartDrop(CONFIG.SEED_ID, dropCount, sx, sy, 1000)
            end

            -- 2. Drop Item Hasil Beli Pack dengan auto-geser ke kanan jika tile penuh
            if hasPackItems and packCfg then
                local px, py = sx, sy
                if packCfg.DropPlacement then
                    if type(packCfg.DropPlacement) == "table" then
                        px, py = packCfg.DropPlacement.x, packCfg.DropPlacement.y
                    elseif type(packCfg.DropPlacement) == "number" and packCfg.DropPlacement > 100 then
                        px = packCfg.DropPlacement % 100
                        py = math.floor(packCfg.DropPlacement / 100)
                    end
                end

                local delayFP = packCfg.DelayFPDrop or 1000
                for _, itemId in ipairs(packCfg.ItemIDOfPack) do
                    local count = bot:getInventory():findItem(itemId)
                    if count > 0 then
                        print(string.format("[Storage] Menjatuhkan %d unit item [ID %d]...", count, itemId))
                        smartDrop(itemId, count, px, py, delayFP)
                    end
                end
            end
        end
    end

    -- Jika tas masih penuh blok (>= 190), kembali ke home untuk break sampai tuntas
    if bot:getInventory():findItem(CONFIG.BLOCK_ID) >= 190 then
        return STATE.BREAK_HOME
    end

    -- Jika ada sisa seed untuk ditanam, lanjutkan plant
    if bot:getInventory():findItem(CONFIG.SEED_ID) > 0 then
        return STATE.PLANT
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
