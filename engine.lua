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
bot:setInterval(Action.move, intervals.move or 0.18)

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
local sessionStats = {
    initialGems = nil,
    gemsSpent = 0,
    packsBought = 0,
    seedsSaved = 0,
    worldsDone = 0,
    startEpoch = os.time and os.time() or 0,
    lastOnlineTime = os.time and os.time() or 0,
}

local function formatNumber(n)
    local s = tostring(math.floor(n or 0))
    local k
    while true do
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

local function getMaladyString()
    local maladyNames = {
        [1] = "Torn Muscle",
        [2] = "Broken Leg",
        [3] = "Chicken Feet",
        [4] = "Grumbleteeth",
        [5] = "Brainworms",
        [6] = "Sweaty Palms",
        [7] = "Appendicitis",
        [8] = "Frog Throat",
        [9] = "G-Virus",
        [10] = "Turtle Flu",
    }
    if not bot or not bot.malady or bot.malady == 0 then
        return "None"
    end
    local mName = maladyNames[bot.malady] or string.format("Malady %d", bot.malady)
    local dur = 0
    pcall(function()
        if bot.getMaladyDuration then dur = bot:getMaladyDuration() or 0 end
    end)
    local durMin = math.floor(dur / 60)
    if durMin > 0 then
        return string.format("%s (%d min)", mName, durMin)
    else
        return mName
    end
end

local function getWorldTreeCounts()
    local readyCount = 0
    local unreadyCount = 0
    local world = bot:isInWorld() and bot:getWorld()
    if world then
        pcall(function()
            for _, tile in ipairs(world:getTilesSafe()) do
                if tile:canHarvest() then
                    readyCount = readyCount + 1
                elseif tile.fg == CONFIG.SEED_ID then
                    unreadyCount = unreadyCount + 1
                end
            end
        end)
    end
    return readyCount, unreadyCount
end

local function getFossilRockCount()
    local count = 0
    local world = bot:isInWorld() and bot:getWorld()
    if world then
        pcall(function()
            for _, tile in ipairs(world:getTilesSafe()) do
                if tile.fg == 3918 then
                    count = count + 1
                end
            end
        end)
    end
    return count
end

local savedMessageId = nil
local lastWebhookSent = 0

local function updateWebhook(currentAction, activeFarm)
    local cfg = CONFIG.WEBHOOK
    if not cfg or not cfg.ENABLED or not cfg.URL or cfg.URL == "" or cfg.URL:find("MASUKKAN_URL") then
        return
    end

    local now = os.time and os.time() or 0
    if (now - lastWebhookSent) < 2 then return end
    lastWebhookSent = now

    local activeMessageId = _G.SAVED_WEBHOOK_MESSAGE_ID
    if not activeMessageId or activeMessageId == "" then
        if cfg.MESSAGE_ID and cfg.MESSAGE_ID ~= "" then
            activeMessageId = tostring(cfg.MESSAGE_ID)
            _G.SAVED_WEBHOOK_MESSAGE_ID = activeMessageId
        end
    end

    -- Buat instance Webhook BARU di setiap panggilan agar field embed tidak menumpuk melebihi batas 25 Discord!
    local webhook = nil
    pcall(function()
        webhook = Webhook.new(cfg.URL)
        webhook.username = "Lucifer Monitor (" .. tostring(bot.name) .. ")"
    end)
    if not webhook then return end

    if activeMessageId and activeMessageId ~= "" then
        webhook.message_id = activeMessageId
    end

    local isOnline = (bot.status == BotStatus.online)
    if isOnline then
        sessionStats.lastOnlineTime = now
    end

    local curGems = bot.gem_count or 0
    if sessionStats.initialGems == nil then
        sessionStats.initialGems = curGems
    end
    local gemGain = curGems - sessionStats.initialGems

    local currentWorld = (bot:isInWorld() and bot:getWorld().name or "world")
    local ping = 0
    pcall(function() if bot.getPing then ping = bot:getPing() or 0 end end)
    local pingStr = string.format("%d ms", ping)
    local botLevelStr = tostring(bot.level or 0)

    -- Status & Title Header
    local titleStr = "Auto Rotation [Online]"
    local statusStr = "online"
    local statusColor = 3066993 -- Hijau
    if not isOnline then
        local offSec = math.max(0, now - sessionStats.lastOnlineTime)
        titleStr = string.format("Auto Rotation [Offline (%ds)]", offSec)
        statusStr = "offline"
        statusColor = 15158332 -- Merah
    end

    local minutesRunning = math.floor((now - sessionStats.startEpoch) / 60)
    local updatedFooter = (minutesRunning > 0) and string.format("Updated %d minutes ago", minutesRunning) or "Updated just now"

    local readyTrees, unreadyTrees = getWorldTreeCounts()
    local fossilCount = getFossilRockCount()
    local storageWorldName = type(CONFIG.STORAGE) == "table" and (CONFIG.STORAGE.world or "-") or tostring(CONFIG.STORAGE or "-")

    webhook.content = ""
    webhook.embed1.use = true
    webhook.embed1.color = statusColor
    webhook.embed1.title = titleStr
    webhook.embed1.description = ""

    pcall(function()
        if webhook.embed1.footer then
            webhook.embed1.footer.text = updatedFooter
        end
    end)

    -- 14 Fields persis sesuai susunan template Bos Anas (selalu tepat 14 fields)
    webhook.embed1:addField("Bot Name", tostring(bot.name or "namebot"), true)
    webhook.embed1:addField("Bot Status", statusStr, true)
    webhook.embed1:addField("Bot Ping", pingStr, true)
    webhook.embed1:addField("Bot Level", botLevelStr, true)
    webhook.embed1:addField("Gems (Gain)", string.format("%s (+%s)", formatNumber(curGems), formatNumber(math.max(0, gemGain))), true)
    webhook.embed1:addField("Current World", currentWorld, true)
    webhook.embed1:addField("Worlds Done", string.format("%d worlds", sessionStats.worldsDone), true)
    webhook.embed1:addField("Gems Spent", formatNumber(sessionStats.gemsSpent), true)
    webhook.embed1:addField("Trees on World", string.format("%d ready\n%d unready", readyTrees, unreadyTrees), true)
    webhook.embed1:addField("Fossil Rock", string.format("%d Fossil Rock", fossilCount), true)
    webhook.embed1:addField("Packs Bought", tostring(sessionStats.packsBought), true)
    webhook.embed1:addField("Seeds Saved", formatNumber(sessionStats.seedsSaved), true)
    webhook.embed1:addField("Storage", storageWorldName, true)
    webhook.embed1:addField("Active Malady", getMaladyString(), true)

    if webhook.message_id and webhook.message_id ~= "" then
        local ok, err = pcall(function() webhook:edit() end)
        if not ok then
            print("[Webhook] Peringatan edit webhook gagal: " .. tostring(err))
        end
    else
        -- Jika MESSAGE_ID kosong di config, buat pesan pertama dengan ?wait=true & auto-capture ID agar bisa di-edit terus
        local captured = false
        if HttpClient and Method and Method.post then
            pcall(function()
                local postUrl = cfg.URL
                if not postUrl:find("wait=true") then
                    postUrl = postUrl .. (postUrl:find("%?") and "&wait=true" or "?wait=true")
                end
                local payload = webhook:makeContent()
                local client = HttpClient.new()
                client.url = postUrl
                client:setMethod(Method.post)
                client.timeout = 10
                client.headers = { ["Content-Type"] = "application/json", ["User-Agent"] = "Lucifer" }
                client.body = payload
                local res = client:request()
                if res.error == 0 and res.body then
                    local mid = res.body:match('"id"%s*:%s*"([%d]+)"')
                    if mid then
                        _G.SAVED_WEBHOOK_MESSAGE_ID = mid
                        webhook.message_id = mid
                        captured = true
                        print("[Webhook] Dashboard dibuat di Discord (Message ID: " .. mid .. "). Update selanjutnya akan selalu meng-edit pesan ini!")
                    end
                end
            end)
        end

        if not captured then
            pcall(function() webhook:send() end)
        end
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

local function isAtDoor()
    local world = bot:getWorld()
    if not world then return false end
    local tile = world:getTile(bot.x, bot.y)
    if not tile then return false end
    local fg = tile.fg
    -- ID 6: Main Door (White Door), ID 7: Door (Wooden Door), ID 12: Portcullis, ID 382: Time-Space Warp, ID 694: Castle Door, ID 4992: Dungeon Door
    if fg == 6 or fg == 7 or fg == 12 or fg == 382 or fg == 694 or fg == 4992 then
        return true
    end
    -- Khusus jika bot berada di baris paling atas spawn (y <= 0)
    if bot.y <= 0 then
        return true
    end
    return false
end

local function isInTargetWorld(target)
    if not bot or not bot:isInWorld() then return false end
    local worldName = type(target) == "table" and target.world or target
    local upper = type(worldName) == "string" and worldName:upper() or worldName
    return bot:isInWorld(worldName) or bot:isInWorld(upper)
end

local function isAtWhiteDoor()
    local world = bot:getWorld()
    if not world then return false end
    local tile = world:getTile(bot.x, bot.y)
    return tile ~= nil and tile.fg == 6
end

-- ========================================================
-- HELPER STORAGE DESTINATION (DOORSEED & DOORPACK)
-- Mendukung pintu terpisah:
-- STORAGE = { world = "world", doorseed = "door", doorpack = "door" }
-- ========================================================
-- ========================================================
-- HELPER HOME DESTINATION (MULTI-WORLD RANDOM HOME)
-- Mendukung single table: { world = "..", door = ".." }
-- maupun multiple worlds: { { world = "..", door = ".." }, ... }
-- ========================================================
local function getHomeDest()
    local cfg = CONFIG.HOME
    if type(cfg) == "string" then
        return { world = cfg, door = "" }
    end
    if type(cfg) == "table" then
        -- Jika array of tables (multi-home)
        if #cfg > 0 then
            math.randomseed(os.time() + (bot.index or 1) + math.random(1, 1000))
            local pick = cfg[math.random(#cfg)]
            if type(pick) == "table" then
                return { world = pick.world or "", door = pick.door or "" }
            elseif type(pick) == "string" then
                return { world = pick, door = "" }
            end
        end
        -- Jika single table { world = "..", door = ".." }
        if cfg.world then
            return { world = cfg.world, door = cfg.door or "" }
        end
    end
    return { world = "", door = "" }
end

local function getStorageDest(storageType)
    local cfg = CONFIG.STORAGE
    if type(cfg) == "string" then
        return { world = cfg, door = "" }
    end
    if type(cfg) ~= "table" then
        return { world = "", door = "" }
    end

    local world = cfg.world or ""
    local door = cfg.door or ""

    if storageType == "seed" then
        local doorSeed = cfg.doorseed or cfg.doorSeed or cfg.door_seed or cfg.door
        return { world = world, door = doorSeed or "" }
    elseif storageType == "pack" then
        local doorPack = cfg.doorpack or cfg.doorPack or cfg.door_pack or cfg.door
        return { world = world, door = doorPack or "" }
    end

    return { world = world, door = door }
end

-- ========================================================
-- HELPER PENGATURAN COLLECT & RANGE
-- Membatasi jarak auto_collect agar tetap 2 blok dari bot
-- ========================================================
local function Collect(state, range)
    bot.auto_collect = state and true or false
    bot.collect_range = range or 2
end

local lastWarpWorld = ""
local lastWarpDoor = ""

local function warp(dest)
    Collect(false) -- Matikan auto_collect setiap kali berpindah world
    local world = type(dest) == "table" and dest.world or dest
    local door = type(dest) == "table" and (dest.door or "") or ""
    local upperWorld = type(world) == "string" and world:upper() or world

    if not waitOnline() then return false end

    -- Jika bot sudah berada di world yang sama
    if (bot:isInWorld(world) or bot:isInWorld(upperWorld)) and bot:isInWorld() then
        -- Jika ada target door berbeda di world yang sama (misal pindah dari doorseed ke doorpack)
        if door ~= "" and (lastWarpDoor ~= door or isAtDoor()) then
            print(string.format("[Warp] Berada di world %s, pindah ke door '%s'...", tostring(world), tostring(door)))
            bot:warp(world, door)
            sleep(1000)
            lastWarpDoor = door
            return true
        end
        return true
    end

    bot:warp(world, door)
    lastWarpWorld = world
    lastWarpDoor = door

    -- Polling setiap 500ms agar begitu subserver transfer selesai bot langsung bergerak (rata-rata 1.5 - 2.5 detik)
    for _ = 1, 40 do
        sleep(500)
        if (bot:isInWorld(world) or bot:isInWorld(upperWorld)) and bot:isInWorld() then
            sleep(600) -- jeda settling streaming tile
            if isAtDoor() and door ~= "" then
                bot:warp(world, door)
                sleep(600)
            end
            lastWarpDoor = door
            updateWebhook("Tiba di World: " .. tostring(world), world)
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

    -- 3. Cek apakah bot berada di Pintu (White Door ID 6 / ID Door ID 8 / Spawn)
    if isAtDoor() then
        local curTile = bot:getWorld() and bot:getWorld():getTile(bot.x, bot.y)
        local curFg = curTile and curTile.fg or 0
        if curFg == 6 and door ~= "" then
            print(string.format("[Guard] Terdeteksi di White Door (ID 6). Re-warp ke door '%s'...", door))
            bot:warp(world, door)
            sleep(600)
        end

        -- Berjalan kembali ke koordinat target (x, y) dari pintu
        if targetX and targetY and bot:getWorld() and bot:getWorld():isValidTile(targetX, targetY) then
            print(string.format("[Guard] Berjalan dari pintu (%d, %d) kembali ke target (%d, %d)...", bot.x, bot.y, targetX, targetY))
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
            if itemId == CONFIG.SEED_ID then
                sessionStats.seedsSaved = sessionStats.seedsSaved + dropped
            end
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
-- AUTO-CURE MALADY (SURG AREA DI WORLD 4AID)
-- Alur otomatis navigasi malady / surg area di world 4AID:
-- 1. Warp ke 4AID -> jalan ke (22, 16) -> masuk portal
-- 2. Jalan ke (61, 12) -> hit adventure key -> jalan ke (58, 15) -> masuk portal
-- 3. Jalan ke (50, 15) -> buka adventure door -> pilih button0 (SURG AREA)
-- 4. Menunggu di SURG AREA (66, 39) sampai malady sembuh total
-- Dilengkapi auto-recovery & reconnect guard tanpa rekursi
-- ========================================================
local function isAutoCureMaladyEnabled()
    if CONFIG.AUTO_CURE_MALADY ~= nil then return CONFIG.AUTO_CURE_MALADY == true end
    if CONFIG.autoCureMalady ~= nil then return CONFIG.autoCureMalady == true end
    if CONFIG.autoMalady ~= nil then return CONFIG.autoMalady == true end
    return false -- Default false jika tidak disetel
end

local function hasMalady()
    -- Sesuai arahan Bos Anas: Jika AUTO_CURE_MALADY = false, abaikan malady 100% agar tidak mengganggu rotasi
    if not isAutoCureMaladyEnabled() then return false, 0 end
    if not bot then return false end
    if bot.malady and type(bot.malady) == "number" and bot.malady ~= 0 then
        return true, bot.malady
    end
    if bot.getMaladyDuration and bot:getMaladyDuration() > 0 then
        return true, bot.malady or 1
    end
    return false, 0
end

local dialogHookRegistered = false
local function sendAdventureDoorPacket(tx, ty, btn)
    local pkt = string.format("action|dialog_return\ndialog_name|adventure_door\ntilex|%d|\ntiley|%d|\nbuttonClicked|%s\n", tx, ty, btn)
    if type(bot.sendPacket) == "function" then
        pcall(function() bot:sendPacket(2, pkt) end)
    elseif type(bot.enter) == "function" then
        pcall(function() bot:enter(btn) end)
    end
end

local function registerDialogHook()
    if dialogHookRegistered then return end
    if type(addEvent) == "function" and type(Event) == "table" and Event.variantlist then
        pcall(function()
            addEvent(Event.variantlist, function(varlist)
                if not varlist or type(varlist.get) ~= "function" then return end
                local v0 = varlist:get(0)
                local name = v0 and (v0.getString and v0:getString() or tostring(v0)) or ""
                if name:find("OnDialogRequest") then
                    local v1 = varlist:get(1)
                    local content = v1 and (v1.getString and v1:getString() or tostring(v1)) or ""
                    if content:find("adventure_door") and content:find("button0") then
                        sendAdventureDoorPacket(50, 15, "button0")
                    end
                end
            end)
            dialogHookRegistered = true
        end)
    end
end

local function walkTo(x, y)
    if not waitOnline() then return false end
    if bot.x == x and bot.y == y then return true end
    local ok = bot:findPath(x, y)
    sleep(500)
    return ok or (bot.x == x and bot.y == y)
end

local function enterPortal(x, y)
    if type(bot.enter) == "function" then
        pcall(function() bot:enter() end)
    end
    bot:hit(x, y)
    sleep(400)
end

local function checkAndCureMalady()
    if not isAutoCureMaladyEnabled() then return false end
    local sakit, maladyId = hasMalady()
    if not sakit then return false end

    local maladyWorld = CONFIG.MALADY_WORLD or "4AID"
    updateWebhook("Menyembuhkan Malady di " .. maladyWorld, "-")
    print(string.format("[AutoMalady] Terdeteksi Malady (ID %s). Menuju %s untuk pengobatan di SURG AREA...",
        tostring(maladyId or "Active"), maladyWorld))

    registerDialogHook()

    while waitOnline() and hasMalady() do
        -- Step 1: Warp ke world 4AID
        print("[AutoMalady] [Step 1] Menuju world " .. maladyWorld .. "...")
        if not warp(maladyWorld) then
            print("[AutoMalady] Gagal warp ke " .. maladyWorld .. ", mencoba lagi...")
            sleep(2000)
        else
            sleep(1000)

            -- Berjalan ke portal (22, 16)
            print("[AutoMalady] [Step 1] Berjalan ke portal (22, 16)...")
            walkTo(22, 16)
            enterPortal(22, 16)
            sleep(1500)

            -- Step 2: Ambil adventure key di (61, 12) & masuk portal (64, 12)
            if waitOnline() and hasMalady() then
                print("[AutoMalady] [Step 2] Mengambil adventure key di (61, 12)...")
                walkTo(61, 12)
                bot:hit(61, 12)
                sleep(800)

                print("[AutoMalady] [Step 2] Berjalan ke portal (58, 15)...")
                walkTo(58, 15)
                enterPortal(58, 15)
                sleep(1500)
            end

            -- Step 3: Berjalan ke adventure door (50, 15) & masuk ke SURG AREA
            if waitOnline() and hasMalady() then
                print("[AutoMalady] [Step 3] Berjalan ke adventure door (50, 15)...")
                walkTo(50, 15)
                if type(bot.enter) == "function" then pcall(function() bot:enter() end) end
                bot:hit(50, 15)
                sleep(500)
                sendAdventureDoorPacket(50, 15, "button0")
                sleep(1000)

                -- Pindah ke spot tunggu SURG AREA di (66, 39)
                walkTo(66, 39)
                print("[AutoMalady] [Selesai] Berhasil tiba di SURG AREA (66, 39). Menunggu pengobatan selesai...")

                -- Menunggu di SURG AREA sampai sembuh (hanya restart jika bot DC atau keluar world 4AID)
                while waitOnline() and hasMalady() do
                    -- Jika bot disconnect / offline
                    if bot.status ~= BotStatus.online then
                        print("[AutoMalady] Bot disconnect saat di SURG AREA. Menunggu reconnect...")
                        while bot.status ~= BotStatus.online do
                            sleep(1000)
                        end
                        print("[AutoMalady] Bot online kembali. Mengulang navigasi ke SURG AREA...")
                        break
                    end

                    -- Jika bot terlempar / berpindah keluar dari world 4AID
                    if not isInTargetWorld(maladyWorld) then
                        print("[AutoMalady] Bot tidak berada di world " .. maladyWorld .. ". Mengulang navigasi...")
                        break
                    end

                    sleep(4000)
                end
            end
        end
    end

    if not hasMalady() then
        print("[AutoMalady] Malady telah sembuh total! Keluar dari SURG AREA & melanjutkan rotasi...")
        updateWebhook("Malady Sembuh (Siap Bekerja)", "-")
        sleep(1000)
        return true
    end

    return false
end

-- ========================================================
-- AUTO-MALADY SHIELD (CHICKEN FEET & GRUMBLETEETH TRIGGER)
-- Digunakan jika AUTO_CURE_MALADY = false:
-- Bot sengaja memicu Chicken Feet (via falling packet) &
-- Grumbleteeth (via auto-spam chat) agar kebal dari Torn Muscle!
-- ========================================================
local function hasAnyMalady()
    if not bot then return false end
    local id = bot.malady or 0
    local dur = 0
    pcall(function() if bot.getMaladyDuration then dur = bot:getMaladyDuration() or 0 end end)
    return (id > 0 and (dur == 0 or dur >= 60)) or (dur > 60)
end

local function sendChickenFeetPacket(pixelX, pixelY)
    if not (GameUpdatePacket and GameUpdatePacket.new and bot.sendRaw) then return end
    pcall(function()
        local p = GameUpdatePacket.new()
        p.type = 0          -- Movement state
        p.flags = 32        -- 0x20 = JUMPING / FALLING state
        p.vec_x = pixelX    -- Target pixel X
        p.vec_y = pixelY    -- Target pixel Y
        p.int_x = -1
        p.int_y = -1
        bot:sendRaw(p)
    end)
end

local function findEmptyAirTile()
    local world = bot:getWorld()
    local bx, by = bot.x or 0, bot.y or 0
    if not world then return bx * 32, by * 32 end
    local radius = 20
    local minDistance = 10

    for y = math.max(0, by - radius), math.min(world.y - 1, by + radius) do
        for x = math.max(0, bx - radius), math.min(world.x - 1, bx + radius) do
            local dist = math.max(math.abs(x - bx), math.abs(y - by))
            if dist >= minDistance then
                local tile = world:getTile(x, y)
                if tile and tile.fg == 0 then
                    return x * 32, y * 32
                end
            end
        end
    end
    return bx * 32, by * 32
end

local function setupChatSpam(enable)
    if bot.auto_spam then
        pcall(function()
            if enable then
                local spam = bot.auto_spam
                spam.interval = 2.4
                spam.randomizer = false
                spam.auto_interval = false
                if spam.messages and type(spam.messages.clear) == "function" then
                    spam.messages:clear()
                    spam.messages:add("f")
                    spam.messages:add("f")
                    spam.messages:add("/status")
                end
                spam.enabled = true
            else
                bot.auto_spam.enabled = false
            end
        end)
    end
end

local function isTornMuscle()
    if not bot then return false end
    local id = bot.malady or 0
    if id == 1 then return true end
    local mName = getMaladyString()
    if mName and mName:find("Torn") then return true end
    return false
end

local function hasHarmlessMalady()
    if not bot then return false end
    local id = bot.malady or 0
    if id == 1 or isTornMuscle() then return false end
    local dur = 0
    pcall(function() if bot.getMaladyDuration then dur = bot:getMaladyDuration() or 0 end end)
    return id > 0 and (dur == 0 or dur >= 60)
end

local function triggerMaladyInfection()
    if hasHarmlessMalady() then
        print(string.format("[AutoMalady] Bot sudah memiliki Malady aman (ID %s). Kebal dari Torn Muscle, lanjut rotasi!", tostring(bot.malady or "Active")))
        return true
    end

    -- Sesuai arahan Bos Anas: Arahkan bot ke world SON100BREAK16 terlebih dahulu sebelum menyalakan mode shield
    local shieldWorld = CONFIG.SHIELD_WORLD or "SON100BREAK16"
    print(string.format("[AutoMalady] [Shield Mode] Menuju world '%s' untuk mengaktifkan Malady Shield...", tostring(shieldWorld)))
    updateWebhook("Menuju World Shield", tostring(shieldWorld))

    if not warp(shieldWorld) then
        print(string.format("[AutoMalady] Gagal warp ke world shield '%s'.", tostring(shieldWorld)))
        return false
    end
    sleep(1200)

    print(string.format("[AutoMalady] Memulai proses infeksi (Chicken Feet / Grumbleteeth) di world %s...", tostring(shieldWorld)))
    updateWebhook("Memicu Malady Shield", tostring(shieldWorld))

    -- Aktifkan spam chat
    setupChatSpam(true)

    local pixelX, pixelY = findEmptyAirTile()
    local endTime = (os.time and os.time() or 0) + 180 -- Maksimal 3 menit
    local packetCount = 0

    while waitOnline() and not hasHarmlessMalady() and not isTornMuscle() and (os.time and os.time() or 0) < endTime do
        sendChickenFeetPacket(pixelX, pixelY)
        packetCount = packetCount + 1
        sleep(500)
    end

    -- Matikan spam chat
    setupChatSpam(false)

    if hasHarmlessMalady() then
        print(string.format("[AutoMalady] SUKSES! Bot terinfeksi Malady aman (ID %s) | Packet: %d. Kebal dari pengurangan damage! Lanjut rotasi...", 
            tostring(bot.malady or "Active"), packetCount))
        return true
    else
        print("[AutoMalady] Batas waktu tercapai / belum terkena. Melanjutkan rotasi...")
        return false
    end
end

local function handleMaladyRoutine()
    if isAutoCureMaladyEnabled() then
        if hasAnyMalady() then
            checkAndCureMalady()
        end
    else
        -- Mode Shield (AUTO_CURE_MALADY = false):
        -- Sesuai arahan Bos Anas: Jika terjangkit Torn Muscle (sisa 30 menit atau kurang),
        -- bot standby di world SHIELD_WORLD (SON100BREAK16) sampai sembuh total!
        if isTornMuscle() then
            local shieldWorld = CONFIG.SHIELD_WORLD or "SON100BREAK16"
            local dur = 0
            pcall(function() if bot.getMaladyDuration then dur = bot:getMaladyDuration() or 0 end end)
            local durMin = math.floor(dur / 60)

            print(string.format("[AutoMalady] Proteksi Torn Muscle Aktif! Bot terjangkit Torn Muscle (~%d min). Menuju %s untuk standby...",
                durMin, tostring(shieldWorld)))
            updateWebhook("Standby Menunggu Torn Muscle Sembuh", tostring(shieldWorld))

            if warp(shieldWorld) then
                sleep(1000)
                while waitOnline() and isTornMuscle() do
                    dur = 0
                    pcall(function() if bot.getMaladyDuration then dur = bot:getMaladyDuration() or 0 end end)
                    durMin = math.floor(dur / 60)
                    print(string.format("[AutoMalady] Standby di %s... Menunggu Torn Muscle sembuh (sisa ~%d min)...", tostring(shieldWorld), durMin))
                    updateWebhook(string.format("Standby Torn Muscle (~%d min)", durMin), tostring(shieldWorld))
                    sleep(15000) -- Cek berkala setiap 15 detik
                end
                print("[AutoMalady] Torn Muscle telah sembuh total! Memulai Mode Shield untuk mendapatkan malady aman...")
            end
        end

        -- Begitu sembuh (atau jika belum punya malady aman), picu infeksi Chicken Feet / Grumbleteeth di SHIELD_WORLD
        if not hasHarmlessMalady() then
            triggerMaladyInfection()
        end
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
            -- Simpan HANYA koordinat primitif {x, y} (Mencegah dangling pointer & Access Violation)
            table.insert(rows[y], { x = tile.x, y = tile.y })
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
    Collect(false)
    local farmName = type(dest) == "table" and dest.world or dest
    updateWebhook("Memanen Pohon (Harvest)", farmName)

    -- Cek & tangani malady sebelum panen
    handleMaladyRoutine()

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
    if #readyTrees == 0 and growingCount == 0 then
        print("[Farm] Menunggu data tile pohon selesai diunduh dari server...")
        sleep(1500)
        readyTrees, growingCount = getZigzagReadyTrees()
    end
    print(string.format("[Farm] Status World: %d pohon siap panen | %d pohon masih dalam pertumbuhan", #readyTrees, growingCount))

    for _, coord in ipairs(readyTrees) do
        if not waitOnline() then return STATE.HARVEST end

        local inv = bot:getInventory()
        local blockCount = inv and inv:findItem(CONFIG.BLOCK_ID) or 0
        if blockCount >= maxBlocks then
            print(string.format("[Farm] Blok di tas mencapai batas (%d). Menuju Home untuk break...", blockCount))
            return STATE.BREAK_HOME
        end

        local seedCount = inv and inv:findItem(CONFIG.SEED_ID) or 0
        if seedCount > 190 then
            print(string.format("[Farm] Seed di tas mencapai %d (> 190). Menuju storage...", seedCount))
            return STATE.STORE
        end

        local reached = bot:findPath(coord.x, coord.y)
        if not reached then
            reached = bot:findPath(coord.x - 1, coord.y) or bot:findPath(coord.x + 1, coord.y)
        end

        -- Query tile segar langsung dari memory world (mencegah Access Violation)
        local curWorld = bot:getWorld()
        local freshTile = curWorld and curWorld:getTile(coord.x, coord.y)

        local isReady = false
        if freshTile then
            pcall(function()
                isReady = freshTile:canHarvest()
            end)
        end

        -- Murni harvest cepat tanpa jeda menanam
        if isReady and reached then
            bot:hit(coord.x, coord.y)
            sleep(140)
            bot:collect(3)
            harvested = harvested + 1
            if harvested % 30 == 0 then
                print(string.format("[Farm] Memanen... %d pohon dipanen (Blok di tas: %d)", harvested, inv:findItem(CONFIG.BLOCK_ID)))
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
    local minY = CONFIG.BREAK_MIN_Y or 5
    local maxY = CONFIG.BREAK_MAX_Y or 45

    for attempt = 1, 3 do
        local world = bot:getWorld()
        if world then
            local limMinY = math.max(2, minY)
            local limMaxY = math.min(world.y - 3, maxY)

            local candidates = {}
            for _, tile in ipairs(world:getTilesSafe()) do
                local sx, sy = tile.x, tile.y
                if sx >= 2 and sx <= (world.x - 2) and sy >= limMinY and sy <= limMaxY then
                    if tile.fg == 0 and tile.fg ~= 6 and tile.fg ~= 7 and tile.fg ~= 12 then
                        local ground = world:getTile(sx, sy + 1)
                        -- Syarat lantai pijakan:
                        -- 1. Ada lantai padat (fg ~= 0) dan bukan Pintu (fg ~= 6, 7, 12)
                        -- 2. BUKAN blok farm yang sedang di-break (ground.fg ~= CONFIG.BLOCK_ID)
                        -- 3. BUKAN seed (ground.fg ~= CONFIG.SEED_ID)
                        if ground and ground.fg ~= 0 and ground.fg ~= 6 and ground.fg ~= 7 and ground.fg ~= 12
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

            -- Acak urutan kandidat spot kosong agar bot memilih lokasi baru secara random
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
        end

        sleep(600) -- Jeda streaming tile jika map baru dibuka
    end

    -- Fallback aman: JANGAN pernah mengembalikan koordinat pintu (y <= 0)!
    -- Selalu kembalikan baris Y yang aman dalam rentang [minY, maxY]
    local safeY = math.min(math.max(minY, 5), maxY)
    local safeX = math.min(math.max(10, bot.x), 90)
    print(string.format("[Home] Peringatan: Spot 3 blok kosong di Y [%d - %d] belum terdeteksi. Mencoba fallback ke (%d, %d)...", minY, maxY, safeX, safeY))
    return safeX, safeY
end

local function doBreakHome(dest)
    local farmName = type(dest) == "table" and dest.world or dest
    local blocks = bot:getInventory():findItem(CONFIG.BLOCK_ID)
    if blocks == 0 then return STATE.PLANT end

    -- Sesuai arahan Bos Anas: Cek & tangani malady sebelum mulai break di Home
    handleMaladyRoutine()

    local activeHome = getHomeDest()
    local homeWorld = activeHome.world
    local homeDoor = activeHome.door or ""

    updateWebhook("Memecahkan Blok di Home (3 Blok Atas Simetris)", farmName)
    print(string.format("[Home] Terpilih Home World: %s (Door: '%s'). Menuju ke lokasi...", homeWorld, homeDoor))
    if not warp(activeHome) then return STATE.BREAK_HOME end

    sleep(1000) -- Tunggu stabilisasi streaming tile Home World dari server

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

    -- Jika posisi berdiri asli berada di Pintu (White Door ID 6 / ID Door ID 8 / y <= 0), cari spot random baru
    if isAtDoor() or standY < 2 then
        print(string.format("[Home] Terdeteksi di Pintu / Spawn (%d, %d). Mencari spot break random yang aman di Y [5 - 45]...", standX, standY))
        local rx, ry = findBreakSpot()
        bot:findPath(rx, ry)
        sleep(400)
        standX, standY = bot.x, bot.y
        print(string.format("[Home] Posisi berdiri aman terbaru: (%d, %d)", standX, standY))
    end

    -- Sesuai arahan Bos Anas: Aktifkan auto_collect dengan jangkauan tepat 2 blok
    Collect(true, 2)

    local targetOffsets = {
        { dx = 0, dy = -1 },
        { dx = -1, dy = -1 },
        { dx = 1, dy = -1 },
    }
    local maxHits = CONFIG.PUNCH_RETRY_MAX or 15
    local placeDelay = (intervals.place or 0.16) * 1000
    local hitDelay = (intervals.hit or 0.18) * 1000
    local lastBlockCount = blocks
    local stuckCycles = 0

    while waitOnline() do
        local inv = bot:getInventory()
        local currentBlocks = inv and inv:findItem(CONFIG.BLOCK_ID) or 0
        if currentBlocks == 0 then
            print("[Home] Seluruh blok di tas sudah selesai dipecahkan!")
            break
        end

        -- Sesuai arahan Bos Anas: Jika di tengah proses break bot terkena malady / Torn Muscle:
        if isAutoCureMaladyEnabled() and hasAnyMalady() then
            Collect(false)
            print("[Home] Terdeteksi Malady di tengah proses break! Menuju 4AID untuk pengobatan di SURG AREA...")
            checkAndCureMalady()
            print("[Home] Malady telah sembuh. Kembali ke Home untuk melanjutkan break...")
            warp(activeHome)
            standX, standY = findBreakSpot()
            bot:findPath(standX, standY)
            sleep(400)
            Collect(true, 2)
        elseif not isAutoCureMaladyEnabled() and isTornMuscle() then
            Collect(false)
            print("[Home] Terdeteksi Torn Muscle di tengah break! Menuju SHIELD_WORLD untuk standby...")
            handleMaladyRoutine()
            print("[Home] Torn Muscle sembuh & Shield aktif. Kembali ke Home untuk melanjutkan break...")
            warp(activeHome)
            standX, standY = findBreakSpot()
            bot:findPath(standX, standY)
            sleep(400)
            Collect(true, 2)
        end

        -- Proteksi reconnect & recovery pintu langsung ke posisi kerja
        reconnectGuard(activeHome, standX, standY)

        -- Sesuai arahan Bos Anas: Jika bot terlempar / berada di Pintu (White Door 6 / ID Door 8 pada 97,0),
        -- atau bot tergeser dari spot kerja, bot otomatis kembali ke spot break atau cari spot baru di Y 5 - Y 45!
        if isAtDoor() or bot.y < 2 or not bot:isInTile(standX, standY) then
            print(string.format("[Home] Bot terdeteksi di (%d, %d), bukan di spot break. Kembali ke (%d, %d)...",
                bot.x, bot.y, standX, standY))
            local pathSuccess = bot:findPath(standX, standY)
            sleep(400)

            -- Jika spot lama terhalang atau bot masih di pintu (seperti di 97,0)
            if not pathSuccess or isAtDoor() or bot.y < 2 then
                print("[Home] Spot lama terhalang / bot masih di pintu. Memindai spot break baru di Y [5 - 45]...")
                local newX, newY = findBreakSpot()
                print(string.format("[Home] Spot break baru terpilih: (%d, %d). Berjalan ke lokasi...", newX, newY))
                bot:findPath(newX, newY)
                sleep(400)
                standX, standY = bot.x, bot.y
            end
        end

        -- Posisi berdiri kerja bot
        local curX, curY = bot.x, bot.y

        -- Pengaman mutlak: Jangan pernah meletakkan blok jika bot masih berada di y < 2 (misal di baris atas / pintu)
        if curY >= 2 and not isAtDoor() then
            local world = bot:getWorld()
            if not world then break end

            -- 1. Letakkan hingga 3 blok tepat di atas kepala posisi bot
            for _, off in ipairs(targetOffsets) do
                local tx = curX + off.dx
                local ty = curY + off.dy
                if ty > 0 and ty < world.y then
                    local target = world:getTile(tx, ty)
                    if target and target.fg == 0 and bot:getInventory():findItem(CONFIG.BLOCK_ID) > 0 then
                        bot:place(tx, ty, CONFIG.BLOCK_ID)
                        sleep(placeDelay)
                    end
                end
            end

            -- 2. Pukul ketiga blok sampai hancur relatif terhadap posisi bot
            local totalHits = 0
            while waitOnline() and totalHits < (maxHits * 3) do
                if isAtDoor() then break end

                local anyBlock = false
                for _, off in ipairs(targetOffsets) do
                    local tx = curX + off.dx
                    local ty = curY + off.dy
                    if ty > 0 and ty < world.y then
                        local cur = bot:getWorld():getTile(tx, ty)
                        if cur and cur.fg ~= 0 then
                            anyBlock = true
                            bot:hit(tx, ty)
                            totalHits = totalHits + 1
                            sleep(hitDelay)
                        end
                    end
                end

                if not anyBlock then break end
            end
            bot:collect(2) -- Jangkauan collect tepat 2 blok

            -- Log progres pemecahan blok berkala & anti-stuck detector
            local newBlocks = bot:getInventory():findItem(CONFIG.BLOCK_ID)
            if newBlocks ~= lastBlockCount then
                if (lastBlockCount - newBlocks) >= 9 or newBlocks <= 10 then
                    print(string.format("[Home] Sedang memecahkan blok... Sisa di tas: %d blok", newBlocks))
                end
                lastBlockCount = newBlocks
                stuckCycles = 0
            else
                stuckCycles = stuckCycles + 1
                if stuckCycles >= 4 then
                    print("[Home] Peringatan: Blok tidak berkurang setelah 4 siklus. Memilih spot break baru di Y [5 - 45]...")
                    local altX, altY = findBreakSpot()
                    bot:findPath(altX, altY)
                    sleep(400)
                    standX, standY = bot.x, bot.y
                    stuckCycles = 0
                end
            end
        else
            sleep(500)
        end

        -- 3. Cek overflow seed saat break (> 190 drop 100 ke storage)
        if bot:getInventory():findItem(CONFIG.SEED_ID) > 190 then
            sleep(1000)
            bot:collect(2)
            Collect(false)
            print(string.format("[Home] Seed di tas mencapai %d (> 190). Menyimpan 100 seed ke storage...", bot:getInventory():findItem(CONFIG.SEED_ID)))
            updateWebhook("Menyimpan 100 Seed ke Storage (Tas Penuh)", farmName)
            local seedStorage = getStorageDest("seed")
            if warp(seedStorage) then
                local dropX = bot.x + 1
                local dropY = bot.y
                smartDrop(CONFIG.SEED_ID, 100, dropX, dropY, 1000)
            end
            warp(activeHome)
            bot:findPath(standX, standY)
            sleep(400)
            standX, standY = bot.x, bot.y
            Collect(true, 2)
        end
    end

    -- Sesuai arahan Bos Anas: Tunggu 1 detik & collect sebelum mematikan auto_collect agar hasil break tercollect sempurna
    sleep(1000)
    bot:collect(2)
    Collect(false)

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
            if boughtCount > 0 then
                sessionStats.packsBought = sessionStats.packsBought + boughtCount
                sessionStats.gemsSpent = sessionStats.gemsSpent + (boughtCount * price)
                updateWebhook("Selesai Beli Pack", farmName)
            end

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
                print("[AutoBuy] Langsung menuju world storage pack untuk drop item pack...")
                updateWebhook("Drop Item Pack ke Storage", farmName)
                local packStorage = getStorageDest("pack")
                if warp(packStorage) then
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
    local seeds = inv and inv:findItem(CONFIG.SEED_ID) or 0
    local packCfg = CONFIG.AUTO_BUY_PACK

    local hasPackItems = false
    if packCfg and packCfg.ENABLED and packCfg.ItemIDOfPack and inv then
        for _, id in ipairs(packCfg.ItemIDOfPack) do
            if inv:findItem(id) > 0 then
                hasPackItems = true
                break
            end
        end
    end

    local seedOver190 = (seeds > 190)
    local needStoreSeed = seedOver190 or (seeds >= (CONFIG.STORE_SEED_MIN or 100))

    -- 1. Drop Seed ke Storage Seed (doorseed)
    if needStoreSeed then
        local seedStorage = getStorageDest("seed")
        updateWebhook("Menyimpan Seed ke Storage", farmName)
        print(string.format("[Storage] Menuju storage seed: %s (Door: '%s')...", seedStorage.world, tostring(seedStorage.door or "")))
        if warp(seedStorage) then
            local sx = bot.x + 1
            local sy = bot.y
            local dropCount = seedOver190 and 100 or seeds
            print(string.format("[Storage] Menyimpan %d seed ke storage (sisa di tas: %d)...", dropCount, seeds - dropCount))
            smartDrop(CONFIG.SEED_ID, dropCount, sx, sy, 1000)
        end
    end

    -- 2. Drop Item Hasil Beli Pack ke Storage Pack (doorpack)
    if hasPackItems and packCfg then
        local packStorage = getStorageDest("pack")
        updateWebhook("Drop Item Pack ke Storage", farmName)
        print(string.format("[Storage] Menuju storage pack: %s (Door: '%s')...", packStorage.world, tostring(packStorage.door or "")))
        if warp(packStorage) then
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
                    print(string.format("[Storage] Menjatuhkan %d unit item [ID %d]...", count, itemId))
                    smartDrop(itemId, count, sx, sy, delayFP)
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
    Collect(false)
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

-- Pengecekan settingan mode rotasi (Rotasi = true / false)
local isLoop = (CONFIG.Rotasi == true or CONFIG.ROTASI == true or CONFIG.rotasi == true)
if isLoop then
    print("[Engine] Mode Rotasi AKTIF (Rotasi = true): Bot akan berputar terus-menerus kembali ke world pertama setelah world terakhir selesai.")
else
    print("[Engine] Mode Sekali Jalan (Rotasi = false): Bot hanya akan menjalankan 1 kali putaran seluruh world lalu selesai.")
end

local round = 0
while true do
    -- Pastikan bot online sebelum memulai putaran (tahan tanpa timeout agar rotasi tidak mati sendiri saat DC)
    while bot.status ~= BotStatus.online do
        print("[Engine] Bot offline / disconnect. Menunggu status online kembali untuk melanjutkan rotasi...")
        sleep(2000)
    end

    round = round + 1
    if isLoop and round > 1 then
        print(string.format("\n[Engine] ========================================"))
        print(string.format("[Engine] MEMULAI ROTASI PUTARAN KE-%d (Kembali ke World Pertama)", round))
        print(string.format("[Engine] ========================================\n"))
        updateWebhook(string.format("Rotasi Putaran Ke-%d", round), "-")
    end

    -- 1. Pengecekan & Pengambilan Pickaxe otomatis saat start / awal putaran
    checkAndEquipPickaxe()

    -- 2. Penanganan Malady Otomatis (Cure ke 4AID jika true / Infeksi Shield jika false)
    handleMaladyRoutine()

    if not CONFIG.FARMS or #CONFIG.FARMS == 0 then
        print("[Engine] Peringatan: Daftar CONFIG.FARMS kosong!")
        break
    end

    for _, currentFarm in ipairs(CONFIG.FARMS) do
        local farmName = type(currentFarm) == "table" and currentFarm.world or currentFarm
        handleMaladyRoutine()
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
                -- Sesuai arahan Bos Anas: Verifikasi ulang sebelum benar-benar pindah world
                print(string.format("[Engine] Memverifikasi ulang world '%s' sebelum pindah...", farmName))
                if warp(currentFarm) then
                    sleep(1000) -- Jeda stabilisasi streaming data tile
                    local finalTrees, stillGrowing = getZigzagReadyTrees()
                    if #finalTrees > 0 then
                        print(string.format("[Engine] Terdeteksi masih ada %d pohon siap panen! Membatalkan pindah world & memulai ulang harvest...", #finalTrees))
                        currentState = STATE.HARVEST
                    else
                        print(string.format("[Engine] Terverifikasi 100%% tidak ada pohon siap panen yang tersisa (%d pohon masih tumbuh). Pindah ke world berikutnya...", stillGrowing))
                        sessionStats.worldsDone = sessionStats.worldsDone + 1
                        updateWebhook("Menyelesaikan World: " .. farmName, farmName)
                        break
                    end
                else
                    break
                end
            end
        end
    end

    -- Jika settingan Rotasi bernilai false, bot hanya jalan 1x putaran lalu selesai
    if not isLoop then
        break
    end

    print(string.format("[Engine] Selesai di world terakhir (Putaran ke-%d selesai). Settingan Rotasi = true aktif: kembali ke world pertama seperti baru mulai...", round))
    sleep(2000)
end

updateWebhook("Seluruh Farm Rotasi Selesai", "-")
print("[Engine] Seluruh farm dalam rotasi selesai diproses.")
