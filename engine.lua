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
bot.leave_world_before_warp = false -- Langsung warp antar-world tanpa exit terlebih dahulu

local intervals = CONFIG.ACTION_INTERVALS or {}
bot:setInterval(Action.hit, intervals.hit or 0.18)
bot:setInterval(Action.place, intervals.place or 0.16)
bot:setInterval(Action.move, intervals.move or 0.20)

local STATE = {
    HARVEST = 1,
    BREAK_HOME = 2,
    BUY_PACK = 3,
    STORE = 4,
    PLANT = 5,
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
    bot.auto_collect = false -- Matikan auto_collect setiap kali berpindah world
    local world = type(dest) == "table" and dest.world or dest
    local door = type(dest) == "table" and (dest.door or "") or ""
    local upperWorld = type(world) == "string" and world:upper() or world

    if not waitOnline() then return false end
    if (bot:isInWorld(world) or bot:isInWorld(upperWorld)) and bot:isInWorld() then
        if isAtWhiteDoor() and door ~= "" then
            bot:warp(world, door)
            sleep(1000)
        end
        return true
    end

    bot:warp(world, door)
    -- Polling setiap 500ms agar begitu subserver transfer selesai bot langsung bergerak (rata-rata 1.5 - 2.5 detik)
    for _ = 1, 40 do
        sleep(500)
        if (bot:isInWorld(world) or bot:isInWorld(upperWorld)) and bot:isInWorld() then
            sleep(600) -- jeda settling streaming tile
            if isAtWhiteDoor() and door ~= "" then
                bot:warp(world, door)
                sleep(600)
            end
            return true
        end
        if not waitOnline(3) then return false end
    end
    return false
end

-- ========================================================
-- RECONNECT & POSITION GUARD (reconnect_guard / erco_connet)
-- Menjaga bot online, auto-warp ke world terakhir saat DC, dan recovery dari White Door ke (x, y)
-- ========================================================
local function reconnectGuard(dest, targetX, targetY)
    local world = type(dest) == "table" and dest.world or dest
    local door = type(dest) == "table" and (dest.door or "") or ""

    -- 1. Cek status bot online atau tidak
    if bot.status ~= BotStatus.online then
        print(string.format("[Guard] Bot offline (Status: %s). Menunggu online kembali...", tostring(bot.status)))
        updateWebhook("Bot Offline / Menunggu Reconnect", world)

        while not waitOnline(5) do
            sleep(1000)
        end
        print("[Guard] Bot sudah online kembali!")
    end

    -- 2. Cek apakah bot berada di world target
    if not bot:isInWorld(world) or not bot:isInWorld() then
        print(string.format("[Guard] Bot belum di world '%s'. Melakukan warp...", world))
        warp({ world = world, door = door })
    end

    -- 3. Cek apakah bot berada di White Door (ID 6)
    if isAtWhiteDoor() then
        print(string.format("[Guard] Terdeteksi di White Door (ID 6). Re-warp ke door '%s'...", door))
        if door ~= "" then
            bot:warp(world, door)
            sleep(600)
        end

        -- Berjalan kembali ke koordinat target (x, y) hanya saat pemulihan dari White Door
        if targetX and targetY and bot:getWorld() and bot:getWorld():isValidTile(targetX, targetY) then
            print(string.format("[Guard] Berjalan dari White Door kembali ke posisi target (%d, %d)...", targetX, targetY))
            bot:findPath(targetX, targetY)
            sleep(400)
        end
    end
end

-- Alias kompatibilitas
local function recoverIfAtWhiteDoor(dest, targetX, targetY)
    reconnectGuard(dest, targetX, targetY)
end

-- ========================================================
-- SMART DROP: Mencegah drop di White Door & Auto-geser ke kanan
-- ========================================================
local function smartDrop(itemId, count, startX, startY, delayDrop)
    local world = bot:getWorld()
    if not world then return end

    local curX = startX or bot.x
    local curY = startY or bot.y
    local maxWorldX = world.x - 2
    local delayFPDrop = delayDrop or 1000

    -- KRUSIAL: Server Growtopia memblokir drop di White Door (Exit / ID 6)!
    local curTile = world:getTile(curX, curY)
    if not curTile or curTile.fg == 6 then
        print("[Storage] Posisi target adalah White Door (Exit). Menjauh dari pintu...")
        curX = curX + 1
    end

    while waitOnline() do
        local inv = bot:getInventory()
        local before = inv:findItem(itemId)
        if before == 0 or count <= 0 then break end

        local toDrop = math.min(count, before)

        if not bot:isInTile(curX, curY) then
            bot:findPath(curX, curY)
            sleep(500)
        end

        -- Pastikan bot tidak berada di White Door saat melakukan drop
        if isAtWhiteDoor() then
            print("[Storage] Bot masih di White Door! Melangkah ke samping...")
            curX = curX + 1
            bot:findPath(curX, curY)
            sleep(500)
        end

        bot:fastDrop(itemId, toDrop)
        bot:drop(itemId, toDrop) -- Fallback standard drop
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
-- COLLECT OBJEK TERCECER (BLOCK & SEED) DI WORLD
-- ========================================================
local function collectFloatingObjects(dest)
    local world = bot:getWorld()
    if not world then return end

    local objects = world:getObjects()
    if not objects or #objects == 0 then return end

    local maxBlocks = CONFIG.MAX_BLOCK_BACKPACK or 190

    for _, obj in ipairs(objects) do
        if not waitOnline() then break end
        recoverIfAtWhiteDoor(dest)

        if obj.id == CONFIG.BLOCK_ID or obj.id == CONFIG.SEED_ID then
            local inv = bot:getInventory()
            if obj.id == CONFIG.BLOCK_ID and inv and inv:findItem(CONFIG.BLOCK_ID) >= maxBlocks then
                break
            end

            local tx = math.floor(obj.x / 32)
            local ty = math.floor(obj.y / 32)

            if world:isValidTile(tx, ty) and bot:findPath(tx, ty) then
                bot:collect(3)
                sleep(200)
            end
        end
    end
end

-- ========================================================
-- AUTO-TRASH SAMPAH (DIJALANKAN SETIAP SELESAI BREAK DI HOME)
-- ========================================================
local function doAutoTrash(farmName)
    local trashCfg = CONFIG.AUTO_TRASH
    if not (trashCfg and trashCfg.ENABLED) then return end

    local inv = bot:getInventory()
    if not inv then return end

    -- Daftar Whitelist ID yang TIDAK BOLEH dibuang
    local keepLookup = {
        [98] = true, -- Pickaxe wajib aman
        [CONFIG.BLOCK_ID] = true,
        [CONFIG.SEED_ID] = true,
    }

    -- Lindungi seluruh item hasil pack
    if CONFIG.AUTO_BUY_PACK and CONFIG.AUTO_BUY_PACK.ItemIDOfPack then
        for _, id in ipairs(CONFIG.AUTO_BUY_PACK.ItemIDOfPack) do
            keepLookup[id] = true
        end
    end

    -- Lindungi custom item yang diatur oleh user
    if trashCfg.KEEP_ITEMS then
        for _, id in ipairs(trashCfg.KEEP_ITEMS) do
            keepLookup[id] = true
        end
    end

    local items = inv:getItems()
    if not items or #items == 0 then return end

    local trashedAny = false
    for _, item in ipairs(items) do
        if not waitOnline() then break end

        -- Jangan buang item yang sedang dipakai (isActive) atau item yang dikecualikan
        if not item.isActive and not keepLookup[item.id] and item.count > 0 then
            local info = getInfo(item.id)
            local itemName = info and info.name or ("ID " .. tostring(item.id))
            print(string.format("[AutoTrash] Membuang %d unit item sampah: %s [ID %d]...", item.count, itemName, item.id))
            bot:fastTrash(item.id, item.count)
            sleep(800)
            trashedAny = true
        end
    end

    if trashedAny then
        print("[AutoTrash] Pembersihan tas selesai.")
        updateWebhook("Pembersihan Tas Selesai (Auto Trash)", farmName)
    end
end

-- ========================================================
-- AUTO TAKE & EQUIP PICKAXE (ID 98) SAAT START
-- ========================================================
local function checkAndEquipPickaxe()
    local pickWorld = CONFIG.PICKAXE_WORLD
    local inv = bot:getInventory()
    local pickCount = inv and inv:findItem(98) or 0

    -- Jika bot sudah punya Pickaxe di tas
    if pickCount > 0 then
        local item = inv:getItem(98)
        if item and not item.isActive then
            print("[Pickaxe] Memakai Pickaxe (ID 98) via bot:wear()...")
            bot:wear(98)
            sleep(500)
        end
        return
    end

    -- Jika belum ada Pickaxe dan world pickaxe dikonfigurasi
    if not (pickWorld and pickWorld.world and pickWorld.world ~= "") then
        print("[Pickaxe] Peringatan: Bot belum punya Pickaxe (98) dan CONFIG.PICKAXE_WORLD belum diisi.")
        return
    end

    print("[Pickaxe] Pickaxe (98) tidak ditemukan di tas! Menuju world pickaxe: " .. tostring(pickWorld.world))
    updateWebhook("Mengambil Pickaxe di World Storage", "-")

    if not warp(pickWorld) then
        print("[Pickaxe] Gagal warp ke world pickaxe!")
        return
    end

    print("[Pickaxe] Berhasil masuk world. Menunggu streaming objek dari server...")
    sleep(1200)

    -- Scan berulang hingga 5 kali agar data NetObject selesai di-stream sepenuhnya
    local foundPickaxe = false
    for attempt = 1, 6 do
        local world = bot:getWorld()
        if world then
            local objects = world:getObjects()
            if objects and #objects > 0 then
                for _, obj in ipairs(objects) do
                    if obj.id == 98 then
                        local tx = math.floor(obj.x / 32)
                        local ty = math.floor(obj.y / 32)
                        print(string.format("[Pickaxe] Objek Pickaxe ditemukan di koordinat (%d, %d). Menuju ke lokasi...", tx, ty))

                        if world:isValidTile(tx, ty) and bot:findPath(tx, ty) then
                            bot:collect(3)
                            sleep(1000)
                            foundPickaxe = true
                            break
                        end
                    end
                end
            end
        end

        if foundPickaxe then break end
        sleep(500)
    end

    if not foundPickaxe then
        print("[Pickaxe] Peringatan: Tidak ada objek Pickaxe (ID 98) tercecer di world ini!")
    end

    -- Cek jumlah pickaxe di tas: taruh kembali kelebihannya agar HANYA tersisa 1 di tas (jumlah - 1)
    local currentPicks = bot:getInventory():findItem(98)
    if currentPicks > 1 then
        local toDropBack = currentPicks - 1
        print(string.format("[Pickaxe] Tas terisi %d pickaxe. Menaruh kembali %d buah ke lantai agar tersisa 1...", currentPicks, toDropBack))
        bot:fastDrop(98, toDropBack)
        sleep(1000)
    end

    -- Wear pickaxe agar aktif di tangan
    if bot:getInventory():findItem(98) > 0 then
        print("[Pickaxe] Memakai Pickaxe (ID 98) via bot:wear()...")
        bot:wear(98)
        sleep(500)
        print("[Pickaxe] Pickaxe aktif di tangan dan bot siap bekerja!")
    end
end

-- ========================================================
-- HELPER NAVIGASI ZIGZAG (SNAKE PATTERN)
-- Mengurutkan pohon & lahan tanam agar bot berjalan zigzag:
-- Baris 1: Kiri -> Kanan (x naik)
-- Baris 2: Kanan -> Kiri (x turun)
-- Mencegah bot berjalan mundur 100 tile bolak-balik setiap pergantian baris!
-- ========================================================
local function getZigzagReadyTrees()
    local world = bot:getWorld()
    if not world then return {}, 0 end

    local rows = {}
    local readyCount = 0
    local growingCount = 0

    for _, tile in ipairs(world:getTilesSafe()) do
        if tile:canHarvest() then
            local y = tile.y
            if not rows[y] then rows[y] = {} end
            table.insert(rows[y], tile)
            readyCount = readyCount + 1
        elseif tile.fg == CONFIG.SEED_ID then
            growingCount = growingCount + 1
        end
    end

    local sortedY = {}
    for y in pairs(rows) do
        table.insert(sortedY, y)
    end
    table.sort(sortedY)

    local zigzagTrees = {}
    for i, y in ipairs(sortedY) do
        local rowTiles = rows[y]
        if i % 2 == 1 then
            table.sort(rowTiles, function(a, b) return a.x < b.x end)
        else
            table.sort(rowTiles, function(a, b) return a.x > b.x end)
        end
        for _, t in ipairs(rowTiles) do
            table.insert(zigzagTrees, t)
        end
    end

    return zigzagTrees, growingCount
end

local function getZigzagPlantSpots()
    local world = bot:getWorld()
    if not world then return {} end

    local rows = {}
    for _, tile in ipairs(world:getTilesSafe()) do
        if tile.fg ~= 0 and tile.fg ~= 6 and tile.fg ~= CONFIG.SEED_ID and not tile:canHarvest() and tile.y > 0 then
            local above = world:getTile(tile.x, tile.y - 1)
            if above and above.fg == 0 then
                local y = tile.y - 1
                if not rows[y] then rows[y] = {} end
                table.insert(rows[y], { x = tile.x, y = y, groundX = tile.x, groundY = tile.y })
            end
        end
    end

    local sortedY = {}
    for y in pairs(rows) do
        table.insert(sortedY, y)
    end
    table.sort(sortedY)

    local zigzagSpots = {}
    for i, y in ipairs(sortedY) do
        local rowSpots = rows[y]
        if i % 2 == 1 then
            table.sort(rowSpots, function(a, b) return a.x < b.x end)
        else
            table.sort(rowSpots, function(a, b) return a.x > b.x end)
        end
        for _, s in ipairs(rowSpots) do
            table.insert(zigzagSpots, s)
        end
    end

    return zigzagSpots
end

-- ========================================================
-- STATE HANDLERS
-- ========================================================
local function doHarvest(dest)
    bot.auto_collect = false
    local farmName = type(dest) == "table" and dest.world or dest
    updateWebhook("Memanen Pohon (Harvest)", farmName)

    if not warp(dest) then return STATE.HARVEST end

    sleep(1000) -- Tunggu stabilisasi streaming seluruh data tile dari server
    local world = bot:getWorld()
    if not world then return STATE.HARVEST end

    -- 1. Ambil objek tercecer di farm
    collectFloatingObjects(dest)

    -- 2. Tanam seluruh seed di tas dengan pola Zigzag sampai lahan kosong benar-benar habis
    local initialSeeds = bot:getInventory():findItem(CONFIG.SEED_ID)
    if initialSeeds > 0 then
        print(string.format("[Farm] Ditemukan %d seed di tas. Menanam pola Zigzag sampai lahan penuh...", initialSeeds))
        local planted = 0
        while waitOnline() and bot:getInventory():findItem(CONFIG.SEED_ID) > 0 do
            local plantSpots = getZigzagPlantSpots()
            if #plantSpots == 0 then
                print(string.format("[Farm] Lahan kosong habis (tertanam %d seed). Sisa di tas: %d. Lanjut ke proses harvest...",
                    planted, bot:getInventory():findItem(CONFIG.SEED_ID)))
                break
            end

            local plantedAny = false
            for _, spot in ipairs(plantSpots) do
                if not waitOnline() or bot:getInventory():findItem(CONFIG.SEED_ID) == 0 then break end
                reconnectGuard(dest, spot.x, spot.y)

                local curAbove = world:getTile(spot.x, spot.y)
                local curGround = world:getTile(spot.groundX, spot.groundY)
                if curAbove and curAbove.fg == 0 and curGround and curGround.fg ~= 0 and curGround.fg ~= 6 and curGround.fg ~= CONFIG.SEED_ID then
                    if bot:findPath(spot.x, spot.y) then
                        bot:place(spot.x, spot.y, CONFIG.SEED_ID)
                        sleep(160)
                        planted = planted + 1
                        plantedAny = true
                    end
                end
            end

            if not plantedAny then break end
        end
    end

    local maxBlocks = CONFIG.MAX_BLOCK_BACKPACK or 190
    local harvested = 0
    local readyTrees, growingCount = getZigzagReadyTrees()
    print(string.format("[Farm] Status World: %d pohon siap panen | %d pohon masih dalam pertumbuhan", #readyTrees, growingCount))

    for _, tile in ipairs(readyTrees) do
        if not waitOnline() then return STATE.HARVEST end
        reconnectGuard(dest, tile.x, tile.y)

        local inv = bot:getInventory()
        if inv:findItem(CONFIG.BLOCK_ID) >= maxBlocks or (inv:findItem(CONFIG.BLOCK_ID) == 0 and inv.emptyslots == 0) then
            print(string.format("[Farm] Blok di tas mencapai batas (%d). Menuju Home untuk break...", inv:findItem(CONFIG.BLOCK_ID)))
            return STATE.BREAK_HOME
        end

        if inv:findItem(CONFIG.SEED_ID) > 190 then
            return STATE.STORE
        end

        local reached = bot:findPath(tile.x, tile.y)
        if not reached then
            reached = bot:findPath(tile.x - 1, tile.y) or bot:findPath(tile.x + 1, tile.y)
        end

        if tile:canHarvest() and reached then
            bot:hit(tile.x, tile.y)
            sleep(180)
            bot:collect(3)
            harvested = harvested + 1

            -- Sesuai arahan Bos Anas: Jika di backpack ada seed, bot langsung harvest dan tanam di tile tersebut!
            -- Jika tidak ada seed di tas, bot hanya harvest seperti biasa tanpa jeda tanam.
            local currentSeeds = bot:getInventory():findItem(CONFIG.SEED_ID)
            if currentSeeds > 0 then
                local curTile = world:getTile(tile.x, tile.y)
                if not curTile or curTile.fg ~= 0 then
                    sleep(100)
                    curTile = world:getTile(tile.x, tile.y)
                end
                if curTile and curTile.fg == 0 then
                    bot:place(tile.x, tile.y, CONFIG.SEED_ID)
                    sleep(160)
                end
            end
        end
    end

    collectFloatingObjects(dest)

    -- Jika ada blok yang berhasil dipanen, pulang ke Home untuk break
    if bot:getInventory():findItem(CONFIG.BLOCK_ID) > 0 then
        return STATE.BREAK_HOME
    end

    -- Cek ulang apakah masih ada pohon siap panen yang tersisa
    local checkRemaining = getZigzagReadyTrees()
    if #checkRemaining > 0 then
        print(string.format("[Farm] Masih ada %d pohon siap panen yang belum terjangkau. Mengulangi putaran...", #checkRemaining))
        return STATE.HARVEST
    end

    print(string.format("[Farm] Seluruh pohon siap panen di world ini telah habis dipanen (%d pohon masih tumbuh).", growingCount))
    return STATE.NEXT_WORLD
end

local function findBreakSpot()
    local world = bot:getWorld()
    if not world then return bot.x, bot.y end

    local candidates = {}
    for _, tile in ipairs(world:getTilesSafe()) do
        local sx, sy = tile.x, tile.y
        if sx >= 2 and sx <= (world.x - 2) and sy >= 2 and sy <= (world.y - 3) then
            if tile.fg == 0 and tile.fg ~= 6 then
                local ground = world:getTile(sx, sy + 1)
                -- Syarat lantai pijakan:
                -- 1. Ada lantai padat (fg ~= 0) dan bukan White Door (fg ~= 6)
                -- 2. BUKAN blok farm yang sedang di-break (ground.fg ~= CONFIG.BLOCK_ID)
                --    agar bot tidak berdiri di atas blok farm yang tertinggal
                -- 3. BUKAN seed (ground.fg ~= CONFIG.SEED_ID)
                if ground and ground.fg ~= 0 and ground.fg ~= 6 
                   and ground.fg ~= CONFIG.BLOCK_ID 
                   and ground.fg ~= CONFIG.SEED_ID then
                    local t1 = world:getTile(sx, sy - 1)
                    local t2 = world:getTile(sx - 1, sy - 1)
                    local t3 = world:getTile(sx + 1, sy - 1)
                    if t1 and t1.fg == 0 and t2 and t2.fg == 0 and t3 and t3.fg == 0 then
                        table.insert(candidates, { x = sx, y = sy })
                    end
                end
            end
        end
    end

    -- Sesuai arahan Bos Anas: Acak urutan kandidat spot kosong agar bot memilih lokasi baru secara random
    if #candidates > 0 then
        math.randomseed(os.time())
        for i = #candidates, 2, -1 do
            local j = math.random(i)
            candidates[i], candidates[j] = candidates[j], candidates[i]
        end

        for _, spot in ipairs(candidates) do
            if bot:findPath(spot.x, spot.y) then
                return spot.x, spot.y
            end
        end
    end

    return bot.x, bot.y
end

local function doBreakHome(dest)
    local farmName = type(dest) == "table" and dest.world or dest
    local blocks = bot:getInventory():findItem(CONFIG.BLOCK_ID)
    if blocks == 0 then return STATE.PLANT end

    local homeWorld = type(CONFIG.HOME) == "table" and CONFIG.HOME.world or CONFIG.HOME
    local homeDoor = type(CONFIG.HOME) == "table" and (CONFIG.HOME.door or "") or ""

    updateWebhook("Memecahkan Blok di Home (3 Blok Atas Simetris)", farmName)
    if not warp(CONFIG.HOME) then return STATE.BREAK_HOME end

    print("[Home] Auto-scan spot 3 blok di atas kepala (mencari lokasi kosong secara random)...")
    local targetX, targetY = findBreakSpot()
    print(string.format("[Home] Target scan random: (%d, %d). Mencoba findPath ke lokasi...", targetX, targetY))

    bot:findPath(targetX, targetY)
    sleep(400)

    -- Sesuai arahan Bos Anas: Cek lokasi BERDIRI ASLI bot saat ini, jangan hanya mengandalkan target findPath!
    local standX, standY = bot.x, bot.y
    if standX ~= targetX or standY ~= targetY then
        print(string.format("[Home] Info: Bot berada di (%d, %d), bukan di target (%d, %d). Menggunakan posisi berdiri asli!",
            standX, standY, targetX, targetY))
    else
        print(string.format("[Home] Sukses tiba di spot: Berdiri (%d, %d)", standX, standY))
    end

    -- Jika posisi berdiri asli berada di White Door (ID 6), re-warp dan cari spot random baru
    if isAtWhiteDoor() then
        print(string.format("[Home] Terdeteksi di White Door (ID 6). Re-warp ke '%s:%s' dan scan lokasi baru...", homeWorld, homeDoor))
        if homeDoor ~= "" then bot:warp(homeWorld, homeDoor) else bot:warp(homeWorld) end
        sleep(600)
        local rx, ry = findBreakSpot()
        bot:findPath(rx, ry)
        sleep(400)
        standX, standY = bot.x, bot.y
        print(string.format("[Home] Posisi berdiri aman terbaru: (%d, %d)", standX, standY))
    end

    bot.auto_collect = true

    local targetOffsets = {
        { dx = 0, dy = -1 },
        { dx = -1, dy = -1 },
        { dx = 1, dy = -1 },
    }
    local maxHits = CONFIG.PUNCH_RETRY_MAX or 15
    local placeDelay = (intervals.place or 0.16) * 1000
    local hitDelay = (intervals.hit or 0.18) * 1000

    while waitOnline() do
        local inv = bot:getInventory()
        if not inv or inv:findItem(CONFIG.BLOCK_ID) == 0 then
            print("[Home] Seluruh blok di tas sudah selesai dipecahkan!")
            break
        end

        -- Proteksi reconnect & recovery White Door langsung ke posisi kerja
        reconnectGuard(CONFIG.HOME, standX, standY)

        -- Selalu ambil posisi BERDIRI ASLI bot saat ini secara dinamis
        local curX, curY = bot.x, bot.y

        -- Sesuai arahan Bos Anas: Jika bot terlempar atau berdiri di White Door (ID 6),
        -- bot otomatis warp(world, id) dan mencari lokasi break baru secara random
        if isAtWhiteDoor() then
            print(string.format("[Home] Bot terlempar/berdiri di White Door (ID 6)! Otomatis re-warp ke '%s:%s'...", homeWorld, homeDoor))
            if homeDoor ~= "" then
                bot:warp(homeWorld, homeDoor)
                sleep(800)
            else
                bot:warp(homeWorld)
                sleep(800)
            end

            print("[Home] Memindai world kembali untuk mencari lokasi break kosong secara random...")
            local newX, newY = findBreakSpot()
            print(string.format("[Home] Spot break baru terpilih: (%d, %d). Berjalan ke lokasi baru...", newX, newY))
            bot:findPath(newX, newY)
            sleep(400)
            standX, standY = bot.x, bot.y
            curX, curY = bot.x, bot.y
            print(string.format("[Home] Melanjutkan break di posisi baru: (%d, %d)", curX, curY))
        end

        local world = bot:getWorld()
        if not world then break end

        -- 1. Letakkan hingga 3 blok tepat di atas kepala posisi ASLI bot
        for _, off in ipairs(targetOffsets) do
            local tx = curX + off.dx
            local ty = curY + off.dy
            local target = world:getTile(tx, ty)
            if target and target.fg == 0 and bot:getInventory():findItem(CONFIG.BLOCK_ID) > 0 then
                bot:place(tx, ty, CONFIG.BLOCK_ID)
                sleep(placeDelay)
            end
        end

        -- 2. Pukul ketiga blok sampai hancur relatif terhadap posisi ASLI bot
        local totalHits = 0
        while waitOnline() and totalHits < (maxHits * 3) do
            if isAtWhiteDoor() then break end

            local anyBlock = false
            for _, off in ipairs(targetOffsets) do
                local tx = curX + off.dx
                local ty = curY + off.dy
                local cur = bot:getWorld():getTile(tx, ty)
                if cur and cur.fg ~= 0 then
                    anyBlock = true
                    bot:hit(tx, ty)
                    totalHits = totalHits + 1
                    sleep(hitDelay)
                end
            end

            if not anyBlock then break end
        end
        bot:collect(3)

        -- 3. Cek overflow seed saat break (> 190 drop 100 ke storage)
        if bot:getInventory():findItem(CONFIG.SEED_ID) > 190 then
            bot.auto_collect = false
            print(string.format("[Home] Seed di tas mencapai %d (> 190). Menyimpan 100 seed ke storage...", bot:getInventory():findItem(CONFIG.SEED_ID)))
            updateWebhook("Menyimpan 100 Seed ke Storage (Tas Penuh)", farmName)
            if warp(CONFIG.STORAGE) then
                local dropX = bot.x + 1
                local dropY = bot.y
                local packCfg = CONFIG.AUTO_BUY_PACK
                if packCfg and packCfg.DropPlacement and type(packCfg.DropPlacement) == "number" and packCfg.DropPlacement > 100 then
                    dropX = packCfg.DropPlacement % 100
                    dropY = math.floor(packCfg.DropPlacement / 100)
                end

                smartDrop(CONFIG.SEED_ID, 100, dropX, dropY, 1000)
            end
            warp(CONFIG.HOME)
            bot:findPath(standX, standY)
            sleep(400)
            standX, standY = bot.x, bot.y
            bot.auto_collect = true
        end
    end

    bot.auto_collect = false

    -- 4. Auto-Trash sampah setelah selesai break di Home
    doAutoTrash(farmName)

    -- 5. Cek Gems di Home
    print("[Info] Gems saat ini: " .. bot.gem_count)

    local packCfg = CONFIG.AUTO_BUY_PACK
    if packCfg and packCfg.ENABLED and packCfg.PricePack and packCfg.PackName then
        if bot.gem_count >= packCfg.PricePack then
            return STATE.BUY_PACK
        end
    end

    if bot:getInventory():findItem(CONFIG.SEED_ID) > 0 then
        return STATE.PLANT
    end

    return STATE.HARVEST
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
            local boughtCount = 0
            while waitOnline() and bot.gem_count >= price do
                bot:buy(packCfg.PackName)
                boughtCount = boughtCount + 1
                sleep(delayBuy)
            end
            print(string.format("[AutoBuy] Selesai beli %d pack. Sisa gems: %d", boughtCount, bot.gem_count))

            -- Sesuai arahan Bos Anas: Begitu selesai beli pack, LANGSUNG drop item pack ke world storage detik itu juga!
            local hasPackItems = false
            local inv = bot:getInventory()
            if packCfg.ItemIDOfPack and inv then
                for _, id in ipairs(packCfg.ItemIDOfPack) do
                    if inv:findItem(id) > 0 then
                        hasPackItems = true
                        break
                    end
                end
            end

            if boughtCount > 0 or hasPackItems then
                print("[AutoBuy] Langsung menuju world storage untuk drop item pack...")
                updateWebhook("Drop Item Pack ke Storage", farmName)
                if warp(CONFIG.STORAGE) then
                    local sx = bot.x + 1
                    local sy = bot.y
                    if packCfg.DropPlacement and type(packCfg.DropPlacement) == "number" and packCfg.DropPlacement > 100 then
                        sx = packCfg.DropPlacement % 100
                        sy = math.floor(packCfg.DropPlacement / 100)
                    end

                    local delayFP = packCfg.DelayFPDrop or 1000
                    for _, itemId in ipairs(packCfg.ItemIDOfPack) do
                        local count = bot:getInventory():findItem(itemId)
                        if count > 0 then
                            print(string.format("[Storage] Menjatuhkan %d unit item pack [ID %d]...", count, itemId))
                            smartDrop(itemId, count, sx, sy, delayFP)
                        end
                    end
                end
            end
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
            local sx = bot.x + 1
            local sy = bot.y
            if packCfg and packCfg.DropPlacement and type(packCfg.DropPlacement) == "number" and packCfg.DropPlacement > 100 then
                sx = packCfg.DropPlacement % 100
                sy = math.floor(packCfg.DropPlacement / 100)
            end

            -- 1. Drop Seed: jika > 190, drop 100 dan sisakan sisanya untuk di-plant
            if needStoreSeed then
                local dropCount = seedOver190 and 100 or seeds
                print(string.format("[Storage] Menyimpan %d seed ke storage (sisa di tas: %d)...", dropCount, seeds - dropCount))
                smartDrop(CONFIG.SEED_ID, dropCount, sx, sy, 1000)
            end

            -- 2. Drop Item Hasil Beli Pack
            if hasPackItems and packCfg then
                local delayFP = packCfg.DelayFPDrop or 1000
                for _, itemId in ipairs(packCfg.ItemIDOfPack) do
                    local count = bot:getInventory():findItem(itemId)
                    if count > 0 then
                        print(string.format("[Storage] Menjatuhkan %d unit item [ID %d]...", count, itemId))
                        smartDrop(itemId, count, sx, sy, delayFP)
                    end
                end
            end
        end
    end

    if bot:getInventory():findItem(CONFIG.SEED_ID) > 0 then
        return STATE.PLANT
    end

    return STATE.HARVEST
end

local function doPlant(dest)
    bot.auto_collect = false
    local farmName = type(dest) == "table" and dest.world or dest
    local seeds = bot:getInventory():findItem(CONFIG.SEED_ID)
    if seeds == 0 then return STATE.HARVEST end

    updateWebhook("Menanam Kembali Seed (Plant)", farmName)
    if not warp(dest) then return STATE.PLANT end

    local world = bot:getWorld()
    if not world then return STATE.PLANT end

    collectFloatingObjects(dest)

    print(string.format("[Plant] Memulai penanaman seed pola Zigzag (tersedia %d seed di tas)...", seeds))
    while waitOnline() and bot:getInventory():findItem(CONFIG.SEED_ID) > 0 do
        local plantSpots = getZigzagPlantSpots()
        if #plantSpots == 0 then
            print("[Plant] Lahan kosong habis / tidak ada tempat lagi. Lanjut ke proses harvest...")
            break
        end

        local plantedAny = false
        for _, spot in ipairs(plantSpots) do
            if not waitOnline() or bot:getInventory():findItem(CONFIG.SEED_ID) == 0 then break end
            reconnectGuard(dest, spot.x, spot.y)

            local curAbove = world:getTile(spot.x, spot.y)
            local curGround = world:getTile(spot.groundX, spot.groundY)
            if curAbove and curAbove.fg == 0 and curGround and curGround.fg ~= 0 and curGround.fg ~= 6 and curGround.fg ~= CONFIG.SEED_ID then
                if bot:findPath(spot.x, spot.y) then
                    bot:place(spot.x, spot.y, CONFIG.SEED_ID)
                    sleep(160)
                    plantedAny = true
                end
            end
        end

        if not plantedAny then break end
    end

    collectFloatingObjects(dest)
    return STATE.HARVEST
end

-- ========================================================
-- ENGINE EXECUTION
-- ========================================================
print("[Engine] Memulai eksekusi rotasi Lucifer v2.86...")
updateWebhook("Engine Dimulai", "-")

-- 1. Pengecekan & Pengambilan Pickaxe otomatis saat start
checkAndEquipPickaxe()

for _, currentFarm in ipairs(CONFIG.FARMS) do
    local farmName = type(currentFarm) == "table" and currentFarm.world or currentFarm
    print("[Engine] Memulai farm: " .. farmName)
    local currentState = (bot:getInventory():findItem(CONFIG.SEED_ID) > 0) and STATE.PLANT or STATE.HARVEST

    while waitOnline() do
        if currentState == STATE.HARVEST then
            currentState = doHarvest(currentFarm)
        elseif currentState == STATE.BREAK_HOME then
            currentState = doBreakHome(currentFarm)
        elseif currentState == STATE.BUY_PACK then
            currentState = doBuyPack(currentFarm)
        elseif currentState == STATE.STORE then
            currentState = doStore(currentFarm)
        elseif currentState == STATE.PLANT then
            currentState = doPlant(currentFarm)
        elseif currentState == STATE.NEXT_WORLD then
            break
        end
    end
end

updateWebhook("Seluruh Farm Rotasi Selesai", "-")
print("[Engine] Seluruh farm dalam rotasi selesai diproses.")
