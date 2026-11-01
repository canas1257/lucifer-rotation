-- ==============================================================================
-- SCRIPT BOT LUCIFER v2.86: WORLD SCANNER & PLANT CHECKER (REVISED v2)
-- Pembuat: Salsa (Kolaborasi & Review: Anna @anna)
-- ==============================================================================

local CONFIG = {
    -- Sumber daftar world:
    -- Jika file ini ada dan berisi baris, bot akan membacanya.
    -- Jika tidak ada / kosong, bot memakai tabel WORLDS di bawah.
    WORLD_LIST_FILE = "world_list.txt",

    -- Daftar world fallback jika tidak pakai file luar:
    -- Format: "NAMA_WORLD" atau "NAMA_WORLD|DOOR_ID"
    WORLDS = {
        "FARMKU1",
        "FARMKU2|DOOR1",
        "FARMKU3",
    },

    -- ID Seed target spesifik:
    -- 0 = Cek SEMUA jenis tanaman/pohon
    -- > 0 = Hanya hitung tanaman dari Seed ID tertentu (contoh: 4585 untuk Pepper Tree)
    TARGET_SEED_ID = 0,

    -- Hanya cek pohon siap panen (abaikan bibit yang masih tumbuh):
    -- true  = Hanya hitung pohon yang canHarvest()
    -- false = Hitung pohon siap panen DAN bibit yang sedang tumbuh
    READY_ONLY = false,

    -- Pengaturan Waktu & Jeda:
    WARP_DELAY = 1500,       -- Jeda tunggu data tile selesai streaming pasca-warp (ms)
    WARP_TIMEOUT = 8,        -- Batas maksimal menunggu masuk world (detik)
    MAX_RECONNECT_WAIT = 60, -- Batas maksimal menunggu bot online saat disconnect (detik)
    NEXT_WORLD_DELAY = 1000, -- Jeda sebelum lanjut ke world berikutnya (ms)

    -- Mode Putaran (Looping):
    -- true  = Bot keliling terus-menerus tanpa henti
    -- false = Bot hanya cek 1 kali keliling daftar world lalu selesai
    LOOP_MODE = false,
    LOOP_INTERVAL = 60,      -- Jeda antar putaran jika LOOP_MODE = true (detik)

    -- File Output TXT:
    OUTPUT = {
        NUKED      = "worlds_nuked.txt",       -- HANYA world yang terkonfirmasi NUKED / Inaccessible
        HAS_PLANT  = "worlds_has_plant.txt",   -- World yang ADA tanaman
        EMPTY      = "worlds_empty.txt",       -- World yang terkonfirmasi KOSONG (0 tanaman)
        FAILED     = "worlds_failed.txt",      -- World yang gagal warp / gagal scan (lag/dc)
        REPORT     = "worlds_scan_report.txt", -- Rekap detail keseluruhan dengan timestamp
    },

    -- Discord Webhook (Opsional untuk monitoring):
    WEBHOOK = {
        ENABLED = false,
        URL = "https://discord.com/api/webhooks/...",
    }
}

-- ==============================================================================
-- INISIALISASI BOT
-- ==============================================================================
local bot = getBot()
if not bot then
    print("[Error] Bot context tidak ditemukan! Jalankan script di console bot Lucifer.")
    return
end

bot.leave_world_before_warp = false

-- State tracking event respon server
local isNukedConfirmed = false
local nukeReasonText = ""
local isServerMaintenance = false

-- ==============================================================================
-- HELPER FILESYSTEM & LOGGING (DENGAN PENGECEKAN RETURN LENGKAP)
-- ==============================================================================
local function getTimestamp()
    if os and os.date then
        return os.date("[%Y-%m-%d %H:%M:%S]")
    end
    return "[SCAN]"
end

local function appendToFile(path, text)
    if not path or path == "" then return false end

    -- 1. Coba fungsi native Lucifer v2.86 (periksa hasil pcall DAN nilai kembalian boolean)
    if type(append) == "function" then
        local ok, result = pcall(append, path, text .. "\n")
        if ok and result == true then
            return true
        end
    end

    -- 2. Fallback I/O standar Lua dengan pengecekan handle & write
    if io and io.open then
        local f, err = io.open(path, "a")
        if f then
            local writeOk = f:write(text .. "\n")
            f:close()
            if writeOk then
                return true
            end
        else
            print(string.format("[Error] Gagal membuka file '%s': %s", tostring(path), tostring(err or "unknown")))
        end
    end

    print(string.format("[Error] Gagal menulis ke file '%s' via append maupun io.open!", tostring(path)))
    return false
end

local function readFileLines(path)
    local lines = {}
    local raw = ""

    if type(read) == "function" then
        local ok, res = pcall(read, path)
        if ok and res and type(res) == "string" then
            raw = res
        end
    end

    if raw == "" and io and io.open then
        local f = io.open(path, "r")
        if f then
            raw = f:read("*a") or ""
            f:close()
        end
    end

    if raw ~= "" then
        for line in raw:gmatch("[^\r\n]+") do
            local clean = line:match("^%s*(.-)%s*$")
            if clean and #clean > 0 and not clean:find("^#") and not clean:find("^//") then
                table.insert(lines, clean)
            end
        end
    end
    return lines
end

local function parseWorldEntry(entry)
    if not entry or entry == "" then return "", "" end
    local w, d = entry:match("^([^|:]+)[|:](.*)$")
    if not w then
        w = entry:match("^([^|:]+)$")
        d = ""
    end
    local cleanW = (w or ""):match("^%s*(.-)%s*$"):upper()
    local cleanD = (d or ""):match("^%s*(.-)%s*$")
    return cleanW, cleanD
end

-- ==============================================================================
-- WEBHOOK NOTIFIKASI
-- ==============================================================================
local function sendWebhookNotification(title, desc, color)
    local cfg = CONFIG.WEBHOOK
    if not cfg or not cfg.ENABLED or not cfg.URL or cfg.URL == "" or cfg.URL:find("webhooks/...") then
        return
    end
    if type(Webhook) == "table" and Webhook.new then
        pcall(function()
            local wh = Webhook.new(cfg.URL)
            wh.username = "Lucifer Checker (" .. tostring(bot.name) .. ")"
            wh.embed1.use = true
            wh.embed1.title = title
            wh.embed1.description = desc
            wh.embed1.color = color or 3447003
            wh:send()
        end)
    end
end

-- ==============================================================================
-- EVENT LISTENER (FILTER PESAN KETAT UNTUK DETEKSI NUKED)
-- ==============================================================================
local function inspectServerMessage(msg)
    if not msg then return end
    local clean = type(removeColor) == "function" and removeColor(msg) or msg
    clean = tostring(clean):lower()

    -- 1. Deteksi Server Maintenance (BUKAN Nuked!)
    if clean:find("maintenance") or clean:find("server is being updated") then
        isServerMaintenance = true
        return
    end

    -- 2. Deteksi Pesan Nuke / Inaccessible Khusus World
    -- Pola resmi Growtopia server: "That world is inaccessible", "World is inaccessible", "nuked"
    if clean:find("is inaccessible") or clean:find("inaccessible, try another") or clean:find("world is inaccessible") or clean:find("world is nuked") or clean:find("has been nuked") then
        isNukedConfirmed = true
        nukeReasonText = clean
    end
end

if type(addEvent) == "function" and type(Event) == "table" then
    if Event.game_message then
        addEvent(Event.game_message, inspectServerMessage)
    end
    if Event.generic_text then
        addEvent(Event.generic_text, inspectServerMessage)
    end
end

-- ==============================================================================
-- HELPER KONEKSI & RECONNECT GUARD (TERUKUR / BOUNDED)
-- ==============================================================================
local function waitOnline(maxSec)
    local limit = maxSec or CONFIG.MAX_RECONNECT_WAIT
    for _ = 1, limit do
        if bot.status == BotStatus.online then
            return true
        end
        -- Deteksi status terminal yang tidak bisa ditunggu
        if bot.status == BotStatus.account_banned or bot.status == BotStatus.location_banned or bot.status == BotStatus.account_suspended then
            print(string.format("[FATAL] Bot terkena sanksi (%s)! Script dihentikan.", tostring(bot.status)))
            return false
        end
        sleep(1000)
    end
    return false
end

-- ==============================================================================
-- WARP DENGAN PUMPING EVENT AKTIF & KLASIFIKASI KETAT
-- ==============================================================================
local function executeWarp(worldName, doorId)
    isNukedConfirmed = false
    nukeReasonText = ""
    isServerMaintenance = false

    if not waitOnline(10) then
        return false, "BOT_OFFLINE"
    end

    local upperTarget = worldName:upper()

    -- Branching strict: jangan oper "" ke argumen kedua
    if doorId and doorId ~= "" then
        bot:warp(upperTarget, doorId)
    else
        bot:warp(upperTarget)
    end

    local elapsed = 0
    local pollStep = 0.5
    local maxWait = CONFIG.WARP_TIMEOUT

    while elapsed < maxWait do
        -- Pompa event selama 0.5 detik agar callback addEvent aktif memproses packet
        if type(listenEvents) == "function" then
            listenEvents(pollStep)
        else
            sleep(math.floor(pollStep * 1000))
        end
        elapsed = elapsed + pollStep

        -- 1. Evaluasi konfirmasi nuke dari respons server
        if isNukedConfirmed then
            return false, "CONFIRMED_NUKED"
        end

        -- 2. Evaluasi server maintenance
        if isServerMaintenance then
            return false, "SERVER_MAINTENANCE"
        end

        -- 3. Cek kedatangan bot di world target
        if (bot:isInWorld(upperTarget) or bot:isInWorld(worldName)) and bot:isInWorld() then
            sleep(CONFIG.WARP_DELAY) -- Jeda streaming tile selesai
            return true, "SUCCESS"
        end

        -- 4. Re-check online
        if bot.status ~= BotStatus.online then
            return false, "DISCONNECT"
        end
    end

    -- Jika timeout tetapi TIDAK ada pesan server konfirmasi nuke
    return false, "WARP_TIMEOUT"
end

-- ==============================================================================
-- SCANNER TANAMAN PADA WORLD (DENGAN PENGECEKAN INTEGRITAS SNAPSHOT)
-- Mengembalikan: success (bool), readyCount (int), growingCount (int), errReason (string)
-- ==============================================================================
local function scanWorldPlants(targetWorldName)
    local upperTarget = targetWorldName:upper()

    -- 1. Verifikasi bot masih berada di world yang benar
    if not bot:isInWorld(upperTarget) and not bot:isInWorld(targetWorldName) then
        return false, 0, 0, "NOT_IN_TARGET_WORLD"
    end

    if bot.status ~= BotStatus.online then
        return false, 0, 0, "BOT_OFFLINE_DURING_SCAN"
    end

    local world = bot:getWorld()
    if not world then
        return false, 0, 0, "WORLD_OBJECT_NIL"
    end

    local tiles = world:getTilesSafe()
    if not tiles or #tiles == 0 then
        return false, 0, 0, "TILES_SNAPSHOT_EMPTY"
    end

    local readyCount = 0
    local growingCount = 0
    local targetSeed = CONFIG.TARGET_SEED_ID or 0
    local readyOnly = CONFIG.READY_ONLY

    for _, tile in ipairs(tiles) do
        if tile.fg and tile.fg ~= 0 then
            -- Pohon siap panen terverifikasi via canHarvest()
            if tile:canHarvest() then
                if targetSeed <= 0 or tile.fg == targetSeed then
                    readyCount = readyCount + 1
                end
            elseif not readyOnly then
                -- Cek bibit/pohon yang sedang tumbuh
                if targetSeed > 0 then
                    -- Filter strict berdasarkan ID seed target
                    if tile.fg == targetSeed then
                        growingCount = growingCount + 1
                    end
                else
                    -- Filter tervalidasi: Seed di Growtopia ber-ID ganjil dan memiliki timer growth pada tile extra
                    local isGrowingSeed = false

                    if tile.hasExtra and tile:hasExtra() then
                        local extra = tile:getExtra()
                        if extra and extra.growth ~= nil then
                            isGrowingSeed = true
                        end
                    end

                    -- Fallback catalog lookup jika extra tidak tersedia
                    if not isGrowingSeed and (tile.fg % 2 == 1) and type(getInfo) == "function" then
                        local info = getInfo(tile.fg)
                        if info and info.name then
                            local lowerName = info.name:lower()
                            if lowerName:find(" seed$") or lowerName:find(" seed ") or (info.action_type and info.action_type == 19) then
                                isGrowingSeed = true
                            end
                        end
                    end

                    if isGrowingSeed then
                        growingCount = growingCount + 1
                    end
                end
            end
        end
    end

    -- 2. Verifikasi ulang bot tidak disconnect selama iterasi snapshot
    if bot.status ~= BotStatus.online or not bot:isInWorld() then
        return false, 0, 0, "DISCONNECT_DURING_SCAN"
    end

    return true, readyCount, growingCount, nil
end

-- ==============================================================================
-- LOGIKA PEMERIKSAAN SATU WORLD
-- ==============================================================================
local function processSingleWorld(worldEntry)
    local worldName, worldDoor = parseWorldEntry(worldEntry)
    if worldName == "" then return end

    local fullLabel = worldName .. (worldDoor ~= "" and ("|" .. worldDoor) or "")
    local timestamp = getTimestamp()

    print(string.format("\n--------------------------------------------------"))
    print(string.format("[%s] Memeriksa: %s...", bot.name, fullLabel))

    -- 1. Eksekusi Warp Pertama
    local success, reason = executeWarp(worldName, worldDoor)

    -- Toleransi lag: jika hanya timeout tanpa konfirmasi nuke, coba retry 1x
    if not success and reason == "WARP_TIMEOUT" then
        print(string.format("[%s] Warp pertama timeout, mencoba ulang 1x...", bot.name))
        sleep(1000)
        success, reason = executeWarp(worldName, worldDoor)
    end

    -- ==========================================================================
    -- 2. EVALUASI HASIL WARP
    -- ==========================================================================

    -- KASUS A: NUKED TERKONFIRMASI
    if not success and reason == "CONFIRMED_NUKED" then
        print(string.format("[HASIL] ⛔ %s => NUKED / INACCESSIBLE (Respon: %s)", fullLabel, tostring(nukeReasonText)))
        appendToFile(CONFIG.OUTPUT.NUKED, fullLabel)
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: NUKED_CONFIRMED | Respon: %s", timestamp, fullLabel, nukeReasonText))
        sendWebhookNotification("⛔ World Nuked Terkonfirmasi", string.format("**World:** `%s`\n**Pesan:** %s", fullLabel, nukeReasonText), 15158332)
        return
    end

    -- KASUS B: SERVER MAINTENANCE
    if not success and reason == "SERVER_MAINTENANCE" then
        print(string.format("[HASIL] ⏸️ %s => GAGAL (SERVER SEDANG MAINTENANCE)", fullLabel))
        appendToFile(CONFIG.OUTPUT.FAILED, string.format("%-18s | Reason: SERVER_MAINTENANCE", fullLabel))
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: FAILED (SERVER_MAINTENANCE)", timestamp, fullLabel))
        return
    end

    -- KASUS C: GAGAL WARP (Timeout / Bot Offline / Lag) -> BUKAN BUKTI NUKE!
    if not success then
        print(string.format("[HASIL] ⚠️ %s => GAGAL WARP (Alasan: %s) -> Ditulis ke FAILED", fullLabel, reason))
        appendToFile(CONFIG.OUTPUT.FAILED, string.format("%-18s | Reason: %s", fullLabel, reason))
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: WARP_FAILED (%s)", timestamp, fullLabel, reason))
        return
    end

    -- ==========================================================================
    -- 3. EVALUASI HASIL SCAN TANAMAN (WORLD BERHASIL DIMASUKI)
    -- ==========================================================================
    local scanOk, ready, growing, scanErr = scanWorldPlants(worldName)

    -- KASUS D: SCAN GAGAL (Snapshot nil / bot DC saat scan) -> JANGAN ANGGAP EMPTY!
    if not scanOk then
        print(string.format("[HASIL] ⚠️ %s => SCAN GAGAL (Alasan: %s) -> Ditulis ke FAILED", fullLabel, tostring(scanErr)))
        appendToFile(CONFIG.OUTPUT.FAILED, string.format("%-18s | Reason: SCAN_FAILED_%s", fullLabel, tostring(scanErr)))
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: SCAN_FAILED (%s)", timestamp, fullLabel, tostring(scanErr)))
        return
    end

    local totalPlants = ready + growing

    -- KASUS E: ADA TANAMAN
    if totalPlants > 0 then
        local detailStr = string.format("Total: %d (Siap Panen: %d, Tumbuh: %d)", totalPlants, ready, growing)
        print(string.format("[HASIL] 🌿 %s => ADA TANAMAN [%s]", fullLabel, detailStr))
        appendToFile(CONFIG.OUTPUT.HAS_PLANT, string.format("%-18s | %s", fullLabel, detailStr))
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: ADA TANAMAN | Ready: %-4d | Growing: %-4d | Total: %-4d",
            timestamp, fullLabel, ready, growing, totalPlants))
        sendWebhookNotification("🌿 Ada Tanaman", string.format("**World:** `%s`\n**Siap Panen:** %d\n**Tumbuh:** %d\n**Total:** %d",
            fullLabel, ready, growing, totalPlants), 3066993)

    -- KASUS F: TERKONFIRMASI KOSONG (Tile valid, bot verified di world, tanaman = 0)
    else
        print(string.format("[HASIL] 🍂 %s => TERKONFIRMASI KOSONG (0 Tanaman)", fullLabel))
        appendToFile(CONFIG.OUTPUT.EMPTY, fullLabel)
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: KOSONG_TERKONFIRMASI", timestamp, fullLabel))
        sendWebhookNotification("🍂 World Kosong", string.format("**World:** `%s`\n**Status:** Bersih / Tanpa Tanaman", fullLabel), 9807270)
    end
end

-- ==============================================================================
-- EKSEKUTOR UTAMA
-- ==============================================================================
local function runScanner()
    print("==================================================")
    print("      LUCIFER WORLD CHECKER BOT v2.86            ")
    print("==================================================")

    while true do
        local worldList = readFileLines(CONFIG.WORLD_LIST_FILE)
        if #worldList == 0 then
            worldList = CONFIG.WORLDS or {}
        end

        if #worldList == 0 then
            print("[Warning] Daftar world kosong! Isi world_list.txt atau CONFIG.WORLDS.")
            break
        end

        print(string.format("\n[Info] Memulai pemeriksaan %d world...", #worldList))

        for index, entry in ipairs(worldList) do
            -- Reconnect guard sebelum lanjut
            if not waitOnline(CONFIG.MAX_RECONNECT_WAIT) then
                print("[Fatal] Bot offline melebihi batas tunggu! Menghentikan rotasi scan.")
                appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s BOT_ABORTED | Bot offline melebihi batas waktu tunggu", getTimestamp()))
                return
            end

            print(string.format("\n[%d/%d] Scanning...", index, #worldList))
            processSingleWorld(entry)

            sleep(CONFIG.NEXT_WORLD_DELAY)
        end

        print("\n==================================================")
        print("          PUTARAN PEMERIKSAAN SELESAI            ")
        print("==================================================")

        if not CONFIG.LOOP_MODE then
            print("[Selesai] Mode 1x putaran selesai. Script berhenti.")
            break
        else
            print(string.format("[Loop] Menunggu %d detik sebelum putaran berikutnya...", CONFIG.LOOP_INTERVAL))
            sleep(CONFIG.LOOP_INTERVAL * 1000)
        end
    end
end

-- ==============================================================================
-- CLEANUP
-- ==============================================================================
function on_stop(errorMessage)
    if type(removeEvents) == "function" then
        removeEvents()
    end
    if errorMessage and errorMessage ~= "" then
        print("[Scanner Error]: " .. errorMessage)
    else
        print("[Scanner Berhenti]")
    end
end

runScanner()
