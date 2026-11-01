-- ==============================================================================
-- SCRIPT BOT LUCIFER v2.86: WORLD SCANNER & PLANT CHECKER
-- Pembuat: Salsa (untuk Bos Anas)
-- Deskripsi:
-- Keliling daftar world untuk cek kondisi:
-- 1. Deteksi world Nuked / Inaccessible.
-- 2. Jika aman (tidak nuked), scan ada pohon/tanaman atau tidak (Ready & Growing).
-- 3. Catat seluruh hasil ke file .txt (Nuked, Ada Tanaman, Kosong, & Laporan Lengkap).
-- ==============================================================================

local CONFIG = {
    -- Sumber daftar world:
    -- Jika file WORLD_LIST_FILE ada, bot akan membaca baris dari file tersebut.
    -- Jika file kosong / tidak ditemukan, bot akan memakai daftar WORLDS di bawah.
    WORLD_LIST_FILE = "world_list.txt",

    -- Daftar world manual (Fallback jika tidak menggunakan file):
    -- Format: "NAMA_WORLD" atau "NAMA_WORLD|DOOR_ID"
    WORLDS = {
        "FARMKU1",
        "FARMKU2|DOOR1",
        "FARMKU3",
    },

    -- ID Seed target spesifik (opsional):
    -- 0 = Cek SEMUA jenis tanaman/pohon secara otomatis
    -- > 0 = Hanya hitung tanaman dari Seed ID tertentu (contoh: 4585 untuk Pepper Tree)
    TARGET_SEED_ID = 0,

    -- Pengaturan Waktu & Jeda:
    WARP_DELAY = 1200,      -- Jeda settling streaming tile pasca-warp (ms)
    WARP_TIMEOUT = 7,       -- Batas maksimal menunggu masuk world (detik)
    NEXT_WORLD_DELAY = 1000,-- Jeda sebelum lanjut ke world berikutnya (ms)

    -- Mode Putaran (Looping):
    -- true  = Bot keliling terus-menerus tanpa henti (setelah world terakhir, ulang dari awal)
    -- false = Bot hanya cek 1 kali keliling daftar world lalu selesai
    LOOP_MODE = false,
    LOOP_INTERVAL = 60,     -- Jeda istirahat antar putaran jika LOOP_MODE = true (detik)

    -- File Output TXT:
    OUTPUT = {
        NUKED      = "worlds_nuked.txt",       -- Daftar world yang terkena NUKED / Inaccessible
        HAS_PLANT  = "worlds_has_plant.txt",   -- Daftar world yang ADA tanaman
        EMPTY      = "worlds_empty.txt",       -- Daftar world yang KOSONG (tidak ada tanaman)
        REPORT     = "worlds_scan_report.txt", -- Rekap detail lengkap dengan timestamp & statistik
    },

    -- Discord Webhook (Opsional untuk pantau hasil scan):
    WEBHOOK = {
        ENABLED = false,
        URL = "https://discord.com/api/webhooks/...",
    }
}

-- ==============================================================================
-- INISIALISASI BOT & VALIDASI LINGKUNGAN
-- ==============================================================================
local bot = getBot()
if not bot then
    print("[Error] Bot context tidak ditemukan! Jalankan script di console bot Lucifer.")
    return
end

bot.leave_world_before_warp = false -- Direct seamless warp tanpa putus ke menu utama

-- State global listener nuked
local isNukedSignal = false
local lastSignalReason = ""

-- ==============================================================================
-- HELPER FILESYSTEM & LOGGING
-- ==============================================================================
local function getTimestamp()
    if os and os.date then
        return os.date("[%Y-%m-%d %H:%M:%S]")
    end
    return "[SCAN]"
end

local function appendToFile(path, text)
    if not path or path == "" then return end
    -- Coba fungsi native Lucifer v2.86
    if type(append) == "function" then
        local ok = pcall(append, path, text .. "\n")
        if ok then return end
    end
    -- Fallback I/O standar Lua
    if io and io.open then
        local f = io.open(path, "a")
        if f then
            f:write(text .. "\n")
            f:close()
        end
    end
end

local function readFileLines(path)
    local lines = {}
    local raw = ""
    if type(read) == "function" then
        local ok, res = pcall(read, path)
        if ok and res then raw = res end
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
-- WEBHOOK NOTIFIKASI (OPSIONAL)
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
-- EVENT LISTENER (DETEKSI SINYAL NUKED / INACCESSIBLE DARI SERVER)
-- ==============================================================================
local function checkMessageForNuke(msg)
    if not msg then return end
    local clean = type(removeColor) == "function" and removeColor(msg) or msg
    clean = tostring(clean):lower()

    if clean:find("inaccessible") or clean:find("nuked") or clean:find("banned") or clean:find("maintenance") then
        isNukedSignal = true
        lastSignalReason = clean
    end
end

if type(addEvent) == "function" and type(Event) == "table" then
    if Event.game_message then
        addEvent(Event.game_message, checkMessageForNuke)
    end
    if Event.generic_text then
        addEvent(Event.generic_text, checkMessageForNuke)
    end
end

-- ==============================================================================
-- HELPER KONEKSI & KEDATANGAN WORLD
-- ==============================================================================
local function waitOnline(maxSec)
    local limit = maxSec or 30
    for _ = 1, limit do
        if bot.status == BotStatus.online then return true end
        sleep(1000)
    end
    return false
end

-- Warp aman dengan signature strict Lucifer v2.86 (tanpa argumen kosong "")
local function safeWarp(worldName, doorId)
    isNukedSignal = false
    lastSignalReason = ""

    if not waitOnline(10) then
        return false, "bot_offline"
    end

    local upperTarget = worldName:upper()

    -- Branching strict: jangan oper "" ke argumen kedua
    if doorId and doorId ~= "" then
        bot:warp(upperTarget, doorId)
    else
        bot:warp(upperTarget)
    end

    -- Polling kedatangan
    local loops = math.floor(CONFIG.WARP_TIMEOUT * 2)
    for _ = 1, loops do
        sleep(500)

        -- Cek respon server jika ada pesan nuked
        if isNukedSignal then
            return false, "nuked_signal"
        end

        -- Cek status bot
        if bot.status == BotStatus.could_not_warp then
            return false, "could_not_warp"
        end

        -- Cek apakah sudah mendarat di world
        if (bot:isInWorld(upperTarget) or bot:isInWorld(worldName)) and bot:isInWorld() then
            sleep(CONFIG.WARP_DELAY) -- Jeda settling streaming tile
            return true, "success"
        end

        if not waitOnline(2) then
            return false, "disconnect"
        end
    end

    return false, "timeout"
end

-- ==============================================================================
-- SCANNER TANAMAN PADA WORLD
-- ==============================================================================
local function scanWorldPlants()
    local world = bot:getWorld()
    if not world then
        return 0, 0, 0
    end

    local readyCount = 0
    local growingCount = 0
    local targetSeed = CONFIG.TARGET_SEED_ID or 0

    local tiles = world:getTilesSafe()
    if not tiles then
        return 0, 0, 0
    end

    for _, tile in ipairs(tiles) do
        if tile.fg and tile.fg ~= 0 then
            -- 1. Cek apakah pohon sudah matang (siap panen)
            if tile:canHarvest() then
                if targetSeed <= 0 or tile.fg == targetSeed then
                    readyCount = readyCount + 1
                end
            else
                -- 2. Cek apakah tanaman masih dalam pertumbuhan
                if targetSeed > 0 then
                    if tile.fg == targetSeed then
                        growingCount = growingCount + 1
                    end
                else
                    -- Deteksi umum pohon / seed yang sedang tumbuh
                    local isSeedOrTree = false
                    if type(getInfo) == "function" then
                        local info = getInfo(tile.fg)
                        if info then
                            local name = (info.name or ""):lower()
                            if name:find("seed") or name:find("tree") or (info.action_type and info.action_type == 19) then
                                isSeedOrTree = true
                            end
                        end
                    end
                    -- Fallback: metadata pertumbuhan pada tile extra
                    if not isSeedOrTree and tile.hasExtra and tile:hasExtra() then
                        local extra = tile:getExtra()
                        if extra and extra.growth ~= nil then
                            isSeedOrTree = true
                        end
                    end

                    if isSeedOrTree then
                        growingCount = growingCount + 1
                    end
                end
            end
        end
    end

    local totalPlants = readyCount + growingCount
    return readyCount, growingCount, totalPlants
end

-- ==============================================================================
-- LOGIKA PEMERIKSAAN SATU WORLD
-- ==============================================================================
local function processSingleWorld(worldEntry)
    local worldName, worldDoor = parseWorldEntry(worldEntry)
    if worldName == "" then return end

    local fullLabel = worldName .. (worldDoor ~= "" and ("|" .. worldDoor) or "")
    print(string.format("\n--------------------------------------------------"))
    print(string.format("[%s] Sedang memeriksa world: %s...", bot.name, fullLabel))

    -- 1. Percobaan Warp
    local success, reason = safeWarp(worldName, worldDoor)

    -- Jika timeout, berikan 1x retry untuk memastikan bukan hanya lag jaringan
    if not success and reason == "timeout" and not isNukedSignal then
        print(string.format("[%s] Warp pertama timeout, mencoba ulang 1x...", bot.name))
        sleep(1000)
        success, reason = safeWarp(worldName, worldDoor)
    end

    local timestamp = getTimestamp()

    -- 2. Evaluasi Hasil: World Nuked / Inaccessible
    if not success then
        local isNuked = (reason == "nuked_signal" or reason == "could_not_warp" or reason == "timeout")
        if isNuked then
            print(string.format("[HASIL] ⛔ %s => NUKED / INACCESSIBLE (Alasan: %s)", fullLabel, tostring(lastSignalReason ~= "" and lastSignalReason or reason)))
            appendToFile(CONFIG.OUTPUT.NUKED, fullLabel)

            local logLine = string.format("%s %-20s | STATUS: NUKED / INACCESSIBLE | Detail: %s",
                timestamp, fullLabel, tostring(lastSignalReason ~= "" and lastSignalReason or reason))
            appendToFile(CONFIG.OUTPUT.REPORT, logLine)

            sendWebhookNotification("⛔ World Nuked Terdeteksi",
                string.format("**World:** `%s`\n**Status:** Nuked / Inaccessible\n**Waktu:** %s", fullLabel, timestamp), 15158332)
            return
        else
            print(string.format("[HASIL] ⚠️ %s => GAGAL MASUK (%s)", fullLabel, reason))
            return
        end
    end

    -- 3. Evaluasi Hasil: World Berhasil Dimasuki (TIDAK NUKED) -> Cek Tanaman
    local ready, growing, total = scanWorldPlants()

    if total > 0 then
        local statusDetail = string.format("Total: %d (Siap Panen: %d, Masih Tumbuh: %d)", total, ready, growing)
        print(string.format("[HASIL] 🌿 %s => ADA TANAMAN [%s]", fullLabel, statusDetail))

        appendToFile(CONFIG.OUTPUT.HAS_PLANT, string.format("%-18s | %s", fullLabel, statusDetail))

        local logLine = string.format("%s %-20s | STATUS: ADA TANAMAN | Ready: %-4d | Growing: %-4d | Total: %-4d",
            timestamp, fullLabel, ready, growing, total)
        appendToFile(CONFIG.OUTPUT.REPORT, logLine)

        sendWebhookNotification("🌿 Ada Tanaman",
            string.format("**World:** `%s`\n**Siap Panen:** %d\n**Masih Tumbuh:** %d\n**Total:** %d", fullLabel, ready, growing, total), 3066993)
    else
        print(string.format("[HASIL] 🍂 %s => KOSONG (TIDAK ADA TANAMAN)", fullLabel))

        appendToFile(CONFIG.OUTPUT.EMPTY, fullLabel)

        local logLine = string.format("%s %-20s | STATUS: KOSONG (TIDAK ADA TANAMAN)", timestamp, fullLabel)
        appendToFile(CONFIG.OUTPUT.REPORT, logLine)

        sendWebhookNotification("🍂 World Kosong",
            string.format("**World:** `%s`\n**Status:** Tidak ada pohon/tanaman", fullLabel), 9807270)
    end
end

-- ==============================================================================
-- EKSEKUTOR UTAMA (KELILING DAFTAR WORLD)
-- ==============================================================================
local function runScanner()
    print("==================================================")
    print("      LUCIFER WORLD CHECKER BOT DIMULAI          ")
    print("==================================================")

    while true do
        -- Ambil daftar world dari file jika tersedia, atau dari tabel CONFIG.WORLDS
        local worldList = readFileLines(CONFIG.WORLD_LIST_FILE)
        if #worldList == 0 then
            worldList = CONFIG.WORLDS or {}
        end

        if #worldList == 0 then
            print("[Warning] Tidak ada daftar world untuk dicek! Periksa WORLD_LIST_FILE atau CONFIG.WORLDS.")
            break
        end

        print(string.format("\n[Info] Memulai pemindaian %d world...", #worldList))

        for index, entry in ipairs(worldList) do
            if not waitOnline(15) then
                print("[Error] Bot offline terlalu lama saat rotasi scanner. Menunggu koneksi kembali...")
                while not waitOnline(10) do sleep(2000) end
            end

            print(string.format("\n[%d/%d] Menuju target...", index, #worldList))
            processSingleWorld(entry)

            sleep(CONFIG.NEXT_WORLD_DELAY)
        end

        print("\n==================================================")
        print("          PUTARAN PEMERIKSAAN SELESAI            ")
        print("==================================================")

        if not CONFIG.LOOP_MODE then
            print("[Selesai] Mode 1x putaran aktif. Script berhenti.")
            break
        else
            print(string.format("[Loop] Menunggu %d detik sebelum putaran berikutnya...", CONFIG.LOOP_INTERVAL))
            sleep(CONFIG.LOOP_INTERVAL * 1000)
        end
    end
end

-- ==============================================================================
-- LIFECYCLE CLEANUP
-- ==============================================================================
function on_stop(errorMessage)
    if type(removeEvents) == "function" then
        removeEvents()
    end
    if errorMessage and errorMessage ~= "" then
        print("[Scanner Stopped with Error]: " .. errorMessage)
    else
        print("[Scanner Finished Normally]")
    end
end

-- Jalankan program
runScanner()
