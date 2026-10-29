-- loader.lua
-- Script ringkas untuk dieksekusi di bot Lucifer
-- Mengambil engine utama secara realtime dari GitHub Raw
-- https://github.com/canas1257/lucifer-rotation

-- ========================================================
-- 1. KONFIGURASI ROTASI & FITUR (Sesuaikan di sini)
-- ========================================================
local CONFIG = {
    -- Daftar world farm yang akan dipanen & ditanam
    -- Format: { world = "NAMA_WORLD", door = "DOOR_ID" } atau string "NAMA_WORLD"
    FARMS = {
        { world = "FARM1", door = "" },
        { world = "FARM2", door = "" },
    },

    -- World untuk memecahkan blok hasil panen
    HOME = { world = "MYHOME", door = "" },

    -- World storage untuk menyimpan seed & hasil item pack
    STORAGE = { world = "MYSTORE", door = "" },

    -- World untuk mengambil Pickaxe jika belum ada di tas saat start
    PICKAXE_WORLD = { world = "WORLDPICK", door = "" },

    -- ID Item Target
    BLOCK_ID = 4584,       -- Contoh: Pepper Tree Block
    SEED_ID = 4585,        -- Contoh: Pepper Tree Seed

    -- Batas & Ambang Toleransi
    BATCH_LIMIT = 20,      -- Maksimal pohon dipanen sebelum pulang ke home
    STORE_SEED_MIN = 100,  -- Minimal seed di inventory sebelum di-drop ke storage
    PUNCH_RETRY_MAX = 15,  -- Batas hit blok sebelum skip (mencegah stuck)

    -- Interval Aksi Bot (Detik)
    ACTION_INTERVALS = {
        hit = 0.18,
        place = 0.16,
        move = 0.20,
    },

    -- ====================================================
    -- Setting For Webhook Live Monitor (webhook_edit)
    -- ====================================================
    WEBHOOK = {
        ENABLED = true,
        URL = "MASUKKAN_URL_WEBHOOK_DISCORD_ANDA",
        MESSAGE_ID = "", -- Jika diisi, bot akan edit pesan ini terus-menerus (Live Dashboard)
    },

    -- ====================================================
    -- Setting For Auto Buy Pack & Drop Storage
    -- ====================================================
    AUTO_BUY_PACK = {
        ENABLED = true,
        PackName = "world_lock_10_pack", -- Pack Name di Store
        PricePack = 20000,               -- Harga Pack dalam Gems
        ItemIDOfPack = { 242 },          -- ItemID hasil dari pack (242 = World Lock)
        DelayBuyPack = 1500,             -- Delay pembelian antar-pack (ms)
        DropPlacement = 1422,            -- Koordinat tile / index drop di storage (1422 -> x:22, y:14)
        DelayDrop = 2000,                -- Delay navigasi sebelum drop (ms)
        DelayFPDrop = 1000,              -- Delay fast drop item (ms)
    },

    -- ====================================================
    -- Setting For Auto Trash (Setiap Selesai Break di Home)
    -- ====================================================
    AUTO_TRASH = {
        ENABLED = true,
        -- Daftar ID item kustom yang ingin disimpan (JANGAN dibuang)
        -- Pickaxe (98), Blok target, Seed target, dan Item hasil Pack otomatis aman!
        KEEP_ITEMS = { 98, 18, 32 }, -- Contoh: 18 (Fist), 32 (Wrench), atau ID item lainnya
    }
}

-- ========================================================
-- 2. LOADER DARI GITHUB RAW (JANGAN DIUBAH)
-- ========================================================
local RAW_ENGINE_URL = "https://raw.githubusercontent.com/canas1257/lucifer-rotation/main/engine.lua"

print("[Loader] Mengunduh engine rotasi dari GitHub...")

local client = HttpClient.new()
client.url = RAW_ENGINE_URL
client:setMethod(Method.get)
client.timeout = 15
client.headers = { ["User-Agent"] = "Lucifer" }

local res = client:request()
if res.error == 0 and res.status == 200 then
    print("[Loader] Engine berhasil diunduh. Memulai kompilasi...")
    _G.CONFIG = CONFIG
    local chunk, err = (loadstring or load)(res.body)
    if chunk then
        chunk(CONFIG)
    else
        print("[Error] Gagal kompilasi engine: " .. tostring(err))
    end
else
    print(string.format("[Error] Gagal mengunduh engine. Status HTTP: %s | Error: %s", tostring(res.status), tostring(res:getError())))
end
