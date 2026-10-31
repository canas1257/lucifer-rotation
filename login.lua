-- ==============================================================================
-- LUCIFER BOT ACCOUNT LOADER & MANAGER (Nurons Lucifer v2.86)
-- Author  : Salsa & Bos Anas
-- QC      : Anna (@anna)
-- Format  : email|mac:rid:wk:ltoken (Satu akun per baris)
-- ==============================================================================

-- ==============================================================================
-- 1. DAFTAR AKUN (Paste baris akun di bawah ini jika dijalankan langsung)
-- ==============================================================================
local ACCOUNTS = [[
-- Paste akun di sini (satu akun per baris):
-- robdaledonbraroseette@gmail.com|D6:88:91:BD:31:2B:F30FADD759D764B5A7462CAD2704DA06:ba340439688721424466a511bdfd5c71:Z0bY...==
]]

-- ==============================================================================
-- 2. KONFIGURASI GLOBAL
-- ==============================================================================
local CONFIG = {
    USE_BYPASS = false,
    PLATFORM_ID = 0,
    AUTO_MALADY = false,
    AUTO_ROTATION = false,
    PACK_NAME = "vending_machine",
    PACK_PRICE = 8000,

    -- Storage Configuration
    SEED_WORLD = "",
    SEED_DOOR = "",
    SEED_ITEM = 4584,
    PACK_WORLD = "",
    PACK_DOOR = "",

    -- Connection & Console Settings
    -- Catatan: Parameter "connect" diteruskan ke tabel opsi addBot(details).
    -- Jika AUTO_CONNECT = true, bot:connect() juga dipanggil secara eksplisit.
    AUTO_CONNECT = false,
    CONSOLE_ENABLED = true,

    -- Auto Spam Configuration
    SPAM_MESSAGES = {
        "Aku akan musnahkan seluruh alien yang datang ke bumi",
        "Aku adalah Super Hero",
        "Akan ku hancurkan Pepper Block ini dalam 1 hit",
        "Gass",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
}

-- ------------------------------------------------------------------------------
-- Helper: Sanitasi & Masking (Mencegah kebocoran kredensial di log/Discord)
-- ------------------------------------------------------------------------------
local function maskEmail(email)
    if not email or type(email) ~= "string" then return "<unknown>" end
    local user, domain = email:match("^([^@]+)@(.+)$")
    if not user or not domain then return "<invalid_email>" end
    if #user <= 2 then
        return user:sub(1, 1) .. "***@" .. domain
    else
        return user:sub(1, 2) .. "***" .. user:sub(-1) .. "@" .. domain
    end
end

-- ------------------------------------------------------------------------------
-- Validator Email (Validasi per-label domain tanpa overengineering)
-- ------------------------------------------------------------------------------
local function isValidEmail(email)
    if not email or type(email) ~= "string" then return false end
    if email:find("%s") or email:find("%.%.") then return false end

    local user, domain = email:match("^([^@]+)@([^@]+)$")
    if not user or not domain then return false end

    -- Validasi bagian user
    if not user:match("^[%w%.%_%+%-]+$") or user:sub(1, 1) == "." or user:sub(-1, -1) == "." then
        return false
    end

    -- Validasi bagian domain
    if not domain:find("%.") or domain:sub(1, 1) == "." or domain:sub(-1, -1) == "." then
        return false
    end

    -- Validasi tiap label domain (mendukung huruf, angka, minus; tanpa awalan/akhiran minus)
    for label in domain:gmatch("[^%.]+") do
        if #label == 0 then return false end
        if not (label:match("^%w[%w%-]*%w$") or label:match("^%w$")) then
            return false
        end
    end

    -- Validasi TLD (minimal 2 karakter alfabet)
    local tld = domain:match("%.([^%.]+)$")
    if not tld or not tld:match("^%a%a+$") then
        return false
    end

    return true
end

-- ------------------------------------------------------------------------------
-- Validator Format Base64 untuk LTOKEN
-- Karakter Base64 valid, panjang kelipatan 4, padding '=' hanya di akhir max 2
-- ------------------------------------------------------------------------------
local function isValidBase64(s)
    if not s or type(s) ~= "string" or #s == 0 or #s % 4 ~= 0 then
        return false
    end
    local nonPad, pads = s:match("^([A-Za-z0-9+/]+)(=*)$")
    if not nonPad or #nonPad == 0 then
        return false
    end
    if #pads > 2 then
        return false
    end
    return true
end

-- ------------------------------------------------------------------------------
-- Parser: Validasi Ketat email|mac:rid:wk:ltoken
-- ------------------------------------------------------------------------------
local function parseAccountLine(line)
    if not line or type(line) ~= "string" then
        return nil, "Tipe data baris tidak valid"
    end

    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed == "" or trimmed:sub(1, 2) == "--" then
        return nil, "EMPTY_LINE"
    end

    local email, sisa = trimmed:match("^([^|]+)|(.+)$")
    if not email or not sisa then
        if isValidEmail(trimmed) then
            return nil, "Format hanya email ditolak (wajib menyertakan mac:rid:wk:ltoken)"
        end
        return nil, "Format tidak valid (harus: email|mac:rid:wk:ltoken)"
    end

    if not isValidEmail(email) then
        return nil, "Format email tidak valid"
    end

    -- Validasi MAC (17 karakter hex format XX:XX:XX:XX:XX:XX)
    local mac, remaining = sisa:match("^(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x):(.+)$")
    if not mac or not remaining then
        return nil, "Format MAC address tidak valid (harus 6 pasang hex)"
    end

    -- Ekstrak RID, WK, dan LTOKEN
    local rid, wk, ltoken = remaining:match("^([^:]+):([^:]+):(.+)$")
    if not rid or not wk or not ltoken then
        return nil, "Struktur RID/WK/Token tidak lengkap (harus dipisah titik dua ':')"
    end

    -- Validasi RID (harus 32 hex)
    if #rid ~= 32 or not rid:match("^%x+$") then
        return nil, "Format RID tidak valid (harus 32 karakter hexadecimal)"
    end

    -- Validasi WK (harus 32 hex)
    if #wk ~= 32 or not wk:match("^%x+$") then
        return nil, "Format WK tidak valid (harus 32 karakter hexadecimal)"
    end

    -- Validasi LTOKEN
    if not isValidBase64(ltoken) then
        return nil, "Format LTOKEN tidak valid (harus Base64 valid)"
    end

    return {
        email = email,
        mac = mac,
        rid = rid,
        wk = wk,
        ltoken = ltoken
    }
end

-- ------------------------------------------------------------------------------
-- World Manager / Storage Setup (Shared Manager)
-- ------------------------------------------------------------------------------
local function addStorageWorld(manager, world, door, storageType, seedId)
    if not world or world == "" or not manager or not manager.addStorage then
        return
    end
    local nameAndDoor = (door and door ~= "") and (world .. ":" .. door) or world
    pcall(function()
        if manager.removeStorage then
            manager:removeStorage(world, storageType)
        end
        manager:addStorage(nameAndDoor, storageType, seedId)
        if manager.selectStorage then
            manager:selectStorage(world, storageType)
        end
    end)
end

local function setupStorages()
    if type(getWorldManager) ~= "function" or type(StorageType) ~= "table" then
        return
    end
    local ok, manager = pcall(getWorldManager)
    if not ok or not manager then return end

    addStorageWorld(manager, CONFIG.SEED_WORLD, CONFIG.SEED_DOOR, StorageType.seed, CONFIG.SEED_ITEM)
    addStorageWorld(manager, CONFIG.PACK_WORLD, CONFIG.PACK_DOOR, StorageType.pack, 0)
end

-- ------------------------------------------------------------------------------
-- Common Bot Configuration (setupBotCommon)
-- ------------------------------------------------------------------------------
local function setupBotCommon(bot)
    if not bot then
        error("Instance bot bernilai nil")
    end

    if bot.getConsole and bot:getConsole() then
        bot:getConsole().enabled = CONFIG.CONSOLE_ENABLED
    end

    bot.bypass_logon = CONFIG.USE_BYPASS
    bot.auto_ban = false

    if bot.auto_spam then
        local spam = bot.auto_spam
        spam.auto_interval = false
        spam.show_emote = false
        spam.randomizer = false
        spam.use_color = true
        spam.messages = CONFIG.SPAM_MESSAGES
        spam.enabled = false
    end

    if bot.auto_malady then
        local malady = bot.auto_malady
        malady.auto_grumbleteeth = false
        malady.auto_chicken_feet = false
        malady.use_home = false
        malady.auto_disconnect = false
        malady.enabled = CONFIG.AUTO_MALADY
    end

    if bot.rotation then
        local rotation = bot.rotation
        rotation.harvest_until_level = false
        rotation.custom_position = false
        bot.gem_limit = CONFIG.PACK_PRICE
        if bot.setPack then
            bot:setPack(CONFIG.PACK_NAME)
        end
        rotation.enabled = CONFIG.AUTO_ROTATION
    end
end

-- ------------------------------------------------------------------------------
-- Process Single Account (Isolasi Error & Zero Credential Leakage)
-- ------------------------------------------------------------------------------
local function processAccount(accountLine, lineNum)
    local parseData, parseErr = parseAccountLine(accountLine)
    if not parseData then
        if parseErr == "EMPTY_LINE" then
            return { status = "SKIPPED_EMPTY", line = lineNum }
        end
        return {
            status = "FAILED_PARSE",
            line = lineNum,
            reason = parseErr
        }
    end

    local masked = maskEmail(parseData.email)
    local details = {
        name = parseData.ltoken,
        display = parseData.email,
        rid = parseData.rid,
        mac = parseData.mac,
        wk = parseData.wk,
        platform = CONFIG.PLATFORM_ID,
        secret = parseData.email,
        connect = CONFIG.AUTO_CONNECT
    }

    if type(addBot) ~= "function" then
        return {
            status = "FAILED_ADD",
            line = lineNum,
            email = masked,
            reason = "ENGINE_ADDBOT_UNAVAILABLE"
        }
    end

    -- Panggil addBot dalam pcall.
    -- Zero Leak Guard: Jangan pernah memasukkan botOrErr mentah ke reason!
    local addOk, botOrErr = pcall(addBot, details)
    if not addOk then
        return {
            status = "FAILED_ADD",
            line = lineNum,
            email = masked,
            reason = "ADD_EXCEPTION"
        }
    end

    if not botOrErr then
        return {
            status = "FAILED_ADD",
            line = lineNum,
            email = masked,
            reason = "ADD_RETURNED_NIL"
        }
    end

    local targetBot = botOrErr

    -- Setup bot common (Zero Leak Guard: jangan masukkan setupErr mentah ke reason)
    local setupOk, setupErr = pcall(setupBotCommon, targetBot)
    if not setupOk then
        return {
            status = "FAILED_SETUP",
            line = lineNum,
            email = masked,
            bot = targetBot,
            reason = "SETUP_EXCEPTION"
        }
    end

    -- Penanganan koneksi eksplisit bila AUTO_CONNECT aktif
    local connectOk = true
    if CONFIG.AUTO_CONNECT and targetBot.connect then
        local cOk, _ = pcall(function() targetBot:connect() end)
        if not cOk then
            connectOk = false
        end
    end

    local isOnline = false
    if BotStatus and targetBot.status == BotStatus.online then
        isOnline = true
    end

    return {
        status = "ADDED",
        line = lineNum,
        email = masked,
        bot = targetBot,
        connect_ok = connectOk,
        is_online = isOnline
    }
end

-- ------------------------------------------------------------------------------
-- Batch Processor
-- ------------------------------------------------------------------------------
local function processAccounts(rawAccountsText)
    setupStorages()

    local results = {
        total_lines = 0,
        added = 0,
        failed_parse = 0,
        failed_add = 0,
        failed_setup = 0,
        online_count = 0,
        connect_fail_count = 0,
        items = {}
    }

    local lineNum = 0
    for line in (rawAccountsText .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        lineNum = lineNum + 1
        local res = processAccount(line, lineNum)
        if res.status ~= "SKIPPED_EMPTY" then
            results.total_lines = results.total_lines + 1
            table.insert(results.items, res)

            if res.status == "ADDED" then
                results.added = results.added + 1
                if res.is_online then
                    results.online_count = results.online_count + 1
                end
                if not res.connect_ok then
                    results.connect_fail_count = results.connect_fail_count + 1
                end
            elseif res.status == "FAILED_PARSE" then
                results.failed_parse = results.failed_parse + 1
            elseif res.status == "FAILED_ADD" then
                results.failed_add = results.failed_add + 1
            elseif res.status == "FAILED_SETUP" then
                results.failed_setup = results.failed_setup + 1
            end
        end
    end

    return results
end

-- ------------------------------------------------------------------------------
-- Format Summary Report (Zero Credential Leakage)
-- ------------------------------------------------------------------------------
local function formatSummaryReport(results)
    local lines = {}
    table.insert(lines, "=== Laporan Penambahan Bot Lucifer ===")
    table.insert(lines, string.format("Total Baris Diproses : %d", results.total_lines))
    table.insert(lines, string.format("Berhasil Ditambahkan : %d", results.added))
    table.insert(lines, string.format("  - Status Online     : %d (Catatan: Ditambahkan != Terkonfirmasi Online)", results.online_count))
    if results.connect_fail_count > 0 then
        table.insert(lines, string.format("  - Gagal bot:connect : %d", results.connect_fail_count))
    end
    table.insert(lines, string.format("Gagal Parsing Format  : %d", results.failed_parse))
    table.insert(lines, string.format("Gagal addBot Engine   : %d", results.failed_add))
    table.insert(lines, string.format("Gagal Setup Config    : %d", results.failed_setup))
    table.insert(lines, "--------------------------------------")

    for _, item in ipairs(results.items) do
        if item.status == "ADDED" then
            local connStr = item.is_online and "ONLINE" or "REGISTERED (Offline/Belum Login)"
            if not item.connect_ok then
                connStr = connStr .. " [CONNECT_EXCEPTION]"
            end
            table.insert(lines, string.format("[Baris %d] [OK] %s -> %s", item.line, item.email, connStr))
        elseif item.status == "FAILED_SETUP" then
            table.insert(lines, string.format("[Baris %d] [WARN] %s -> Bot terdaftar, namun setup gagal: %s", item.line, item.email, item.reason))
        elseif item.status == "FAILED_ADD" then
            table.insert(lines, string.format("[Baris %d] [ERR] %s -> Gagal addBot: %s", item.line, item.email or "<unknown>", item.reason))
        elseif item.status == "FAILED_PARSE" then
            table.insert(lines, string.format("[Baris %d] [ERR] Format tidak valid: %s", item.line, item.reason))
        end
    end

    return table.concat(lines, "\n")
end

-- ==============================================================================
-- Auto Execution (Jika dijalankan langsung di Lucifer dan ACCOUNTS terisi)
-- ==============================================================================
local hasExecutableAccount = false
for rawLine in ACCOUNTS:gmatch("[^\r\n]+") do
    local trimmed = rawLine:match("^%s*(.-)%s*$")
    if trimmed ~= "" and trimmed:sub(1, 2) ~= "--" then
        hasExecutableAccount = true
        break
    end
end

if hasExecutableAccount then
    local res = processAccounts(ACCOUNTS)
    print(formatSummaryReport(res))
end

-- Ekspor modul untuk unit testing dan integrasi Node.js
return {
    CONFIG = CONFIG,
    maskEmail = maskEmail,
    isValidEmail = isValidEmail,
    isValidBase64 = isValidBase64,
    parseAccountLine = parseAccountLine,
    setupBotCommon = setupBotCommon,
    setupStorages = setupStorages,
    processAccount = processAccount,
    processAccounts = processAccounts,
    formatSummaryReport = formatSummaryReport
}
