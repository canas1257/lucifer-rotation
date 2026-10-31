-- ==============================================================================
-- UNIT TEST SUITE: Lucifer Bot Account Loader (login.lua)
-- ==============================================================================

local function runTests()
    local passed = 0
    local failed = 0

    local function assertEq(expected, actual, testName)
        if expected == actual then
            passed = passed + 1
            print("  [PASS] " .. testName)
        else
            failed = failed + 1
            print("  [FAIL] " .. testName .. " -> Expected: " .. tostring(expected) .. ", Got: " .. tostring(actual))
        end
    end

    local function assertTrue(condition, testName)
        if condition then
            passed = passed + 1
            print("  [PASS] " .. testName)
        else
            failed = failed + 1
            print("  [FAIL] " .. testName .. " -> Expected true, Got false")
        end
    end

    -- Setup Mock Lucifer Environment
    _G.BotStatus = { offline = 0, online = 1, logon_fail = 2 }
    _G.StorageType = { seed = 1, pack = 2 }

    local mockAddedBots = {}
    local simulateAddBotFail = false
    local simulateAddBotLeakException = false
    local simulateSetupFail = false
    local simulateSetupLeakException = false
    local simulateConnectLeakException = false
    local simulateMissingConnectMethod = false
    local simulateStatusPanic = false
    local simulateStorageFail = false

    _G.addBot = function(details)
        if simulateAddBotFail then
            return nil
        end
        if simulateAddBotLeakException then
            -- Simulasi error internal engine yang memuntahkan token
            error("INTERNAL_ENGINE_PANIC_LEAK_TOKEN: " .. tostring(details.name))
        end

        local mockBot = {
            name = details.name,
            display = details.display,
            rid = details.rid,
            mac = details.mac,
            wk = details.wk,
            platform = details.platform,
            secret = details.secret,
            _raw_status = BotStatus.offline,
            bypass_logon = false,
            auto_ban = false,
            gem_limit = 0,
            getConsole = function(self)
                return { enabled = false }
            end,
            setPack = function(self, pack)
                self.pack_name = pack
            end,
            auto_spam = {},
            auto_malady = {},
            rotation = {}
        }

        if not simulateMissingConnectMethod then
            mockBot.connect = function(self)
                if simulateConnectLeakException then
                    error("CONNECT_SOCKET_PANIC_LEAK_TOKEN: " .. tostring(self.name))
                end
                self.connect_called = true
            end
        end

        -- Metatable untuk simulasi status panic
        setmetatable(mockBot, {
            __index = function(t, k)
                if k == "status" then
                    if simulateStatusPanic then
                        error("STATUS_PROPERTY_READ_PANIC")
                    end
                    return t._raw_status
                end
                return rawget(t, k)
            end
        })

        if simulateSetupFail then
            mockBot.getConsole = function()
                error("Console subsystem failed")
            end
        end
        if simulateSetupLeakException then
            mockBot.getConsole = function()
                error("SETUP_PANIC_LEAK_TOKEN: " .. tostring(mockBot.name))
            end
        end

        table.insert(mockAddedBots, mockBot)
        return mockBot
    end

    _G.getWorldManager = function()
        return {
            removeStorage = function(self, w, t) end,
            addStorage = function(self, nd, t, id)
                if simulateStorageFail then
                    error("STORAGE_SUBSYSTEM_DISK_FULL")
                end
            end,
            selectStorage = function(self, w, t) end
        }
    end

    local loader = require("login")

    print("\n--- 1. Testing Sanitization & Masking ---")
    assertEq("sy***a@example.com", loader.maskEmail("synthetic.alpha@example.com"), "Mask standard email")
    assertEq("ab***z@domain.com", loader.maskEmail("abcxyz@domain.com"), "Mask short email")
    assertEq("a***@co.id", loader.maskEmail("ab@co.id"), "Mask 2-letter user email")
    assertEq("<invalid_email>", loader.maskEmail("invalid-email"), "Mask invalid email")

    print("\n--- 2. Testing Domain-Label Email Validator ---")
    assertTrue(loader.isValidEmail("synthetic@example.com"), "Valid simple email")
    assertTrue(loader.isValidEmail("user@sub2.example.com"), "Valid sub2 domain email")
    assertTrue(loader.isValidEmail("user@sub2.example123.com"), "Valid sub2 domain with digits")
    assertTrue(loader.isValidEmail("user.name+gt-1@sub-server.domain.co.id"), "Valid complex email with plus, dash, dots")
    assertTrue(not loader.isValidEmail("notanemail"), "Reject email without @")
    assertTrue(not loader.isValidEmail("user@@domain.com"), "Reject double @")
    assertTrue(not loader.isValidEmail("user @domain.com"), "Reject space in email")
    assertTrue(not loader.isValidEmail("user..name@domain.com"), "Reject consecutive dots")
    assertTrue(not loader.isValidEmail("user@domain.123"), "Reject numeric TLD")
    assertTrue(not loader.isValidEmail("user@domain.c"), "Reject single-letter TLD")
    assertTrue(not loader.isValidEmail("user@-domain.com"), "Reject leading dash in domain label")
    assertTrue(not loader.isValidEmail("user@domain-.com"), "Reject trailing dash in domain label")

    print("\n--- 3. Testing Base64 Format Validator ---")
    assertTrue(loader.isValidBase64("VG9rZW4x"), "Valid Base64 without padding")
    assertTrue(loader.isValidBase64("VG9rZW4="), "Valid Base64 with 1 padding")
    assertTrue(loader.isValidBase64("VG=="), "Valid Base64 with 2 paddings")
    assertTrue(not loader.isValidBase64("===="), "Reject all padding ====")
    assertTrue(not loader.isValidBase64("VG=rZW4="), "Reject padding in middle")
    assertTrue(not loader.isValidBase64("V==="), "Reject 3 paddings")
    assertTrue(not loader.isValidBase64("VG9rZ"), "Reject length not multiple of 4")
    assertTrue(not loader.isValidBase64("VG9rZW4@"), "Reject invalid character @")
    assertTrue(not loader.isValidBase64(""), "Reject empty string")

    print("\n--- 4. Testing Strict Parser: Valid Cases (Synthetic Fixtures) ---")
    local syntheticToken = "VGVzdFN5bnRoZXRpY0Jhc2U2NFRva2VuRm9yVW5pdFRlc3RzT25seURvTm90VXNlMTIzNDU2Nzg5MA=="
    local sampleLine = "synthetic.alpha@example.com|11:22:33:AA:BB:CC:0123456789ABCDEF0123456789ABCDEF:FEDCBA9876543210FEDCBA9876543210:" .. syntheticToken
    local data, err = loader.parseAccountLine(sampleLine)
    assertTrue(data ~= nil, "Valid line successfully parsed")
    if data then
        assertEq("synthetic.alpha@example.com", data.email, "Parsed email matches")
        assertEq("11:22:33:AA:BB:CC", data.mac, "Parsed MAC matches")
        assertEq("0123456789ABCDEF0123456789ABCDEF", data.rid, "Parsed RID matches (32 hex)")
        assertEq("FEDCBA9876543210FEDCBA9876543210", data.wk, "Parsed WK matches (32 hex)")
        assertEq(syntheticToken, data.ltoken, "Parsed LTOKEN matches")
    end

    print("\n--- 5. Testing Strict Parser: Invalid & Rejected Cases ---")
    local _, errEmailOnly = loader.parseAccountLine("someone@example.com")
    assertTrue(errEmailOnly ~= nil and errEmailOnly:find("ditolak"), "Email-only line strictly rejected (no dummy login)")

    local _, errNoPipe = loader.parseAccountLine("someone@example.com:AA:BB:CC:DD:EE:FF")
    assertTrue(errNoPipe ~= nil, "Missing pipe delimiter rejected")

    local _, errBadEmail = loader.parseAccountLine("bad-email|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:VG9rZW4=")
    assertEq("Format email tidak valid", errBadEmail, "Malformed email rejected")

    local _, errBadMac = loader.parseAccountLine("test@example.com|AA:BB:CC:DD:EE:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:VG9rZW4=")
    assertTrue(errBadMac ~= nil and errBadMac:find("MAC"), "Malformed MAC address rejected")

    local _, errBadRid = loader.parseAccountLine("test@example.com|AA:BB:CC:DD:EE:FF:SHORT_HEX:aaaabbbbccccddddeeeeffff00001111:VG9rZW4=")
    assertTrue(errBadRid ~= nil and errBadRid:find("RID"), "Short/invalid RID rejected")

    local _, errBadWk = loader.parseAccountLine("test@example.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:NOT_HEX_CHARS_AT_ALL_XXXX_YYYY:VG9rZW4=")
    assertTrue(errBadWk ~= nil and errBadWk:find("WK"), "Non-hex WK rejected")

    local _, errEmptyToken = loader.parseAccountLine("test@example.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:")
    assertTrue(errEmptyToken ~= nil, "Empty LTOKEN rejected")

    local _, errBadB64Token = loader.parseAccountLine("test@example.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:====")
    assertTrue(errBadB64Token ~= nil and errBadB64Token:find("Base64"), "Invalid Base64 token (====) rejected")

    print("\n--- 6. Testing Zero Credential Leakage in Engine/Setup Exceptions ---")
    local sensitiveToken = "U1VQRVJfU0VDUkVUX1NZTlRIRVRJQ19UT0tFTl9ERU1PXzEyMw=="

    -- 6A: Engine addBot exception throwing raw token
    simulateAddBotLeakException = true
    local resEnginePanic = loader.processAccount("panic.test@example.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:" .. sensitiveToken, 1)
    assertEq("FAILED_ADD", resEnginePanic.status, "Engine panic caught as FAILED_ADD")
    assertEq("ADD_EXCEPTION", resEnginePanic.reason, "Reason is constant ADD_EXCEPTION")
    simulateAddBotLeakException = false

    -- 6B: SetupBotCommon exception throwing raw token
    simulateSetupLeakException = true
    local resSetupPanic = loader.processAccount("panic.setup@example.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:" .. sensitiveToken, 2)
    assertEq("FAILED_SETUP", resSetupPanic.status, "Setup panic caught as FAILED_SETUP")
    assertEq("SETUP_EXCEPTION", resSetupPanic.reason, "Reason is constant SETUP_EXCEPTION")
    simulateSetupLeakException = false

    -- 6C: Check report does NOT leak sensitiveToken
    local mockResultsPanic = {
        total_lines = 2, added = 0, failed_parse = 0, failed_add = 1, failed_setup = 1, online_count = 0, connect_fail_count = 0,
        storage_ok = true, storage_status = "OK",
        items = { resEnginePanic, resSetupPanic }
    }
    local panicReport = loader.formatSummaryReport(mockResultsPanic)
    assertTrue(not panicReport:find(sensitiveToken), "Summary report strictly NEVER contains sensitive token on exceptions")
    assertTrue(not panicReport:find("LEAK"), "Summary report does NOT contain exception internals")

    print("\n--- 7. Testing AUTO_CONNECT Edge Cases ---")
    -- 7A: Connect socket exception
    loader.CONFIG.AUTO_CONNECT = true
    simulateConnectLeakException = true
    local resConnPanic = loader.processAccount("conn.panic@example.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:" .. sensitiveToken, 3)
    assertEq("ADDED", resConnPanic.status, "Account added despite connect exception")
    assertEq(false, resConnPanic.connect_ok, "connect_ok is false on connect exception")
    assertEq("CONNECT_EXCEPTION", resConnPanic.connect_status, "connect_status reports CONNECT_EXCEPTION")
    simulateConnectLeakException = false

    -- 7B: Missing connect method on targetBot
    simulateMissingConnectMethod = true
    local resMissingConn = loader.processAccount("missing.conn@example.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:" .. sensitiveToken, 4)
    assertEq("ADDED", resMissingConn.status, "Account added when connect method is missing")
    assertEq(false, resMissingConn.connect_ok, "connect_ok is false when connect method missing")
    assertEq("CONNECT_UNAVAILABLE", resMissingConn.connect_status, "connect_status reports CONNECT_UNAVAILABLE")
    simulateMissingConnectMethod = false
    loader.CONFIG.AUTO_CONNECT = false

    print("\n--- 8. Testing Status Property Read Exception Resilience ---")
    -- Simulasi membaca bot.status melempar runtime exception
    simulateStatusPanic = true
    local resStatusPanic = loader.processAccount("panic.status@example.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:" .. sensitiveToken, 5)
    assertEq("ADDED", resStatusPanic.status, "Account added and survives status getter panic")
    assertEq(false, resStatusPanic.is_online, "is_online defaults safely to false on getter error")
    simulateStatusPanic = false

    print("\n--- 9. Testing Storage Setup Failure Reporting ---")
    loader.CONFIG.SEED_WORLD = "STORAGE_WORLD"
    simulateStorageFail = true
    local storageResults = loader.processAccounts("synthetic.alpha@example.com|11:22:33:AA:BB:CC:0123456789ABCDEF0123456789ABCDEF:FEDCBA9876543210FEDCBA9876543210:VGVzdFRva2Vu==\n")
    assertEq(false, storageResults.storage_ok, "Storage failure is captured and reported (not swallowed)")
    assertEq("STORAGE_ADD_EXCEPTION", storageResults.storage_status, "Storage failure status code is explicit")
    local storageReport = loader.formatSummaryReport(storageResults)
    assertTrue(storageReport:find("GAGAL") ~= nil, "Summary report explicitly notes Storage Setup GAGAL")
    simulateStorageFail = false
    loader.CONFIG.SEED_WORLD = ""

    print("\n--- 10. Testing Batch Processing & Summary Report ---")
    local batchInput = [[
    -- Baris komentar ini harus diabaikan
    synthetic.alpha@example.com|11:22:33:AA:BB:CC:0123456789ABCDEF0123456789ABCDEF:FEDCBA9876543210FEDCBA9876543210:VGVzdFN5bnRoZXRpY0Jhc2U2NFRva2VuRm9yVW5pdFRlc3RzT25seURvTm90VXNlMTIzNDU2Nzg5MA==
    corrupted_line_without_delimiter
    emailonly@example.com
    synthetic.beta@sub2.example123.com|AA:BB:CC:11:22:33:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:VGVzdFRva2VuMTIz
    ]]

    local results = loader.processAccounts(batchInput)
    assertEq(4, results.total_lines, "Processed 4 non-empty, non-comment lines")
    assertEq(2, results.added, "2 valid accounts successfully added")
    assertEq(2, results.failed_parse, "2 invalid accounts caught by strict parser")
    assertEq(0, results.online_count, "Newly registered bots correctly reported offline (Added != Online)")

    local report = loader.formatSummaryReport(results)
    assertTrue(report:find("Total Baris Diproses : 4") ~= nil, "Report displays total lines")
    assertTrue(report:find("Berhasil Ditambahkan : 2") ~= nil, "Report displays added count")
    assertTrue(report:find("Catatan: Ditambahkan != Terkonfirmasi Online") ~= nil, "Report notes Added != Online")
    print(report)

    print(string.format("\n=========================================="))
    print(string.format("TEST RESULTS: %d PASSED, %d FAILED", passed, failed))
    print(string.format("=========================================="))

    if failed > 0 then
        os.exit(1)
    end
end

runTests()
