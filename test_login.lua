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
            status = BotStatus.offline,
            bypass_logon = false,
            auto_ban = false,
            gem_limit = 0,
            getConsole = function(self)
                return { enabled = false }
            end,
            setPack = function(self, pack)
                self.pack_name = pack
            end,
            connect = function(self)
                if simulateConnectLeakException then
                    error("CONNECT_SOCKET_PANIC_LEAK_TOKEN: " .. tostring(self.name))
                end
                self.connect_called = true
            end,
            auto_spam = {},
            auto_malady = {},
            rotation = {}
        }

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

    local storageCallLog = {}
    _G.getWorldManager = function()
        return {
            removeStorage = function(self, w, t)
                table.insert(storageCallLog, "remove:" .. tostring(w))
            end,
            addStorage = function(self, nd, t, id)
                table.insert(storageCallLog, "add:" .. tostring(nd) .. ":" .. tostring(t) .. ":" .. tostring(id))
            end,
            selectStorage = function(self, w, t)
                table.insert(storageCallLog, "select:" .. tostring(w))
            end
        }
    end

    local loader = require("login")

    print("\n--- 1. Testing Sanitization & Masking ---")
    assertEq("ro***e@gmail.com", loader.maskEmail("robdaledonbraroseette@gmail.com"), "Mask standard email")
    assertEq("ab***z@domain.com", loader.maskEmail("abcxyz@domain.com"), "Mask short email")
    assertEq("a***@co.id", loader.maskEmail("ab@co.id"), "Mask 2-letter user email")
    assertEq("<invalid_email>", loader.maskEmail("invalid-email"), "Mask invalid email")

    print("\n--- 2. Testing Domain-Label Email Validator ---")
    assertTrue(loader.isValidEmail("user@gmail.com"), "Valid simple email")
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

    print("\n--- 4. Testing Strict Parser: Valid Cases ---")
    local sampleValidToken = "Z0bYjfTAUb6REpPTJl/Fo6KKYlWjBUHFSJeMoCsrmjS7AOiotorq9B0NsXS7PKeyVdmSJMcDjaefgM0q1racZlcGRzhyeQ2bpX8AXBOBMa/2hAtsQ6TQrmT62DUR3yP1IM6QzW8yMQGR1ExkMIhKSRMEOQIsisnZ+3oMxtwPbmtjb+qlxr9YUtar8ooPjDMU8R4+FetWVGNkv5b8D7UB12LdJwg/NuZQ8JzVo8qxJI8MVsnsupCMfifqicCwlaq3mrfkl2kvH69veY+2naVFxc4nj/GQe8Sp8Jh/syLNDGkM0ZQvEN3NZK1Xfd52qShUUTWkqXgO1MfMGJgoUBrO8BEYLPnFjaly86BTNpeofIhqA8y+8O9v0zFncFf3OuQlR+UKJbAPweAb+36efN4TCTOl9LRQ5t8qhUZGshEAAKIMiPR9YzmPA0c9xGFTrF2WjwxjsFTRLB1/u1c96jIWsA=="
    local sampleLine = "robdaledonbraroseette@gmail.com|D6:88:91:BD:31:2B:F30FADD759D764B5A7462CAD2704DA06:ba340439688721424466a511bdfd5c71:" .. sampleValidToken
    local data, err = loader.parseAccountLine(sampleLine)
    assertTrue(data ~= nil, "Valid line successfully parsed")
    if data then
        assertEq("robdaledonbraroseette@gmail.com", data.email, "Parsed email matches")
        assertEq("D6:88:91:BD:31:2B", data.mac, "Parsed MAC matches")
        assertEq("F30FADD759D764B5A7462CAD2704DA06", data.rid, "Parsed RID matches (32 hex)")
        assertEq("ba340439688721424466a511bdfd5c71", data.wk, "Parsed WK matches (32 hex)")
        assertEq(sampleValidToken, data.ltoken, "Parsed LTOKEN matches")
    end

    print("\n--- 5. Testing Strict Parser: Invalid & Rejected Cases ---")
    local _, errEmailOnly = loader.parseAccountLine("someone@gmail.com")
    assertTrue(errEmailOnly ~= nil and errEmailOnly:find("ditolak"), "Email-only line strictly rejected (no dummy login)")

    local _, errNoPipe = loader.parseAccountLine("someone@gmail.com:AA:BB:CC:DD:EE:FF")
    assertTrue(errNoPipe ~= nil, "Missing pipe delimiter rejected")

    local _, errBadEmail = loader.parseAccountLine("bad-email|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:VG9rZW4=")
    assertEq("Format email tidak valid", errBadEmail, "Malformed email rejected")

    local _, errBadMac = loader.parseAccountLine("test@mail.com|AA:BB:CC:DD:EE:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:VG9rZW4=")
    assertTrue(errBadMac ~= nil and errBadMac:find("MAC"), "Malformed MAC address rejected")

    local _, errBadRid = loader.parseAccountLine("test@mail.com|AA:BB:CC:DD:EE:FF:SHORT_HEX:aaaabbbbccccddddeeeeffff00001111:VG9rZW4=")
    assertTrue(errBadRid ~= nil and errBadRid:find("RID"), "Short/invalid RID rejected")

    local _, errBadWk = loader.parseAccountLine("test@mail.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:NOT_HEX_CHARS_AT_ALL_XXXX_YYYY:VG9rZW4=")
    assertTrue(errBadWk ~= nil and errBadWk:find("WK"), "Non-hex WK rejected")

    local _, errEmptyToken = loader.parseAccountLine("test@mail.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:")
    assertTrue(errEmptyToken ~= nil, "Empty LTOKEN rejected")

    local _, errBadB64Token = loader.parseAccountLine("test@mail.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:====")
    assertTrue(errBadB64Token ~= nil and errBadB64Token:find("Base64"), "Invalid Base64 token (====) rejected")

    print("\n--- 6. Testing Zero Credential Leakage in Engine/Setup Exceptions ---")
    local sensitiveToken = "U1VQRVJfU0VDUkVUX0xUT0tFTl9ET19OT1RfTEVBS19URVNUXzEyMw=="

    -- 6A: Engine addBot exception throwing raw token
    simulateAddBotLeakException = true
    local resEnginePanic = loader.processAccount("panic.test@gmail.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:" .. sensitiveToken, 1)
    assertEq("FAILED_ADD", resEnginePanic.status, "Engine panic caught as FAILED_ADD")
    assertEq("ADD_EXCEPTION", resEnginePanic.reason, "Reason is constant ADD_EXCEPTION")
    simulateAddBotLeakException = false

    -- 6B: SetupBotCommon exception throwing raw token
    simulateSetupLeakException = true
    local resSetupPanic = loader.processAccount("panic.setup@gmail.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:" .. sensitiveToken, 2)
    assertEq("FAILED_SETUP", resSetupPanic.status, "Setup panic caught as FAILED_SETUP")
    assertEq("SETUP_EXCEPTION", resSetupPanic.reason, "Reason is constant SETUP_EXCEPTION")
    simulateSetupLeakException = false

    -- 6C: Check report does NOT leak sensitiveToken
    local mockResultsPanic = {
        total_lines = 2, added = 0, failed_parse = 0, failed_add = 1, failed_setup = 1, online_count = 0, connect_fail_count = 0,
        items = { resEnginePanic, resSetupPanic }
    }
    local panicReport = loader.formatSummaryReport(mockResultsPanic)
    assertTrue(not panicReport:find(sensitiveToken), "Summary report strictly NEVER contains sensitive token on exceptions")
    assertTrue(not panicReport:find("LEAK"), "Summary report does NOT contain exception internals")

    print("\n--- 7. Testing AUTO_CONNECT & Connect Exception ---")
    loader.CONFIG.AUTO_CONNECT = true
    simulateConnectLeakException = true
    local resConnPanic = loader.processAccount("panic.conn@gmail.com|AA:BB:CC:DD:EE:FF:11112222333344445555666677778888:aaaabbbbccccddddeeeeffff00001111:" .. sensitiveToken, 3)
    assertEq("ADDED", resConnPanic.status, "Account added despite connect exception")
    assertEq(false, resConnPanic.connect_ok, "connect_ok is false on connect exception")
    simulateConnectLeakException = false
    loader.CONFIG.AUTO_CONNECT = false

    print("\n--- 8. Testing Batch Processing & Summary Report ---")
    local batchInput = [[
    -- Baris komentar ini harus diabaikan
    robdaledonbraroseette@gmail.com|D6:88:91:BD:31:2B:F30FADD759D764B5A7462CAD2704DA06:ba340439688721424466a511bdfd5c71:Z0bYjfTAUb6REpPTJl/Fo6KKYlWjBUHFSJeMoCsrmjS7AOiotorq9B0NsXS7PKeyVdmSJMcDjaefgM0q1racZlcGRzhyeQ2bpX8AXBOBMa/2hAtsQ6TQrmT62DUR3yP1IM6QzW8yMQGR1ExkMIhKSRMEOQIsisnZ+3oMxtwPbmtjb+qlxr9YUtar8ooPjDMU8R4+FetWVGNkv5b8D7UB12LdJwg/NuZQ8JzVo8qxJI8MVsnsupCMfifqicCwlaq3mrfkl2kvH69veY+2naVFxc4nj/GQe8Sp8Jh/syLNDGkM0ZQvEN3NZK1Xfd52qShUUTWkqXgO1MfMGJgoUBrO8BEYLPnFjaly86BTNpeofIhqA8y+8O9v0zFncFf3OuQlR+UKJbAPweAb+36efN4TCTOl9LRQ5t8qhUZGshEAAKIMiPR9YzmPA0c9xGFTrF2WjwxjsFTRLB1/u1c96jIWsA==
    corrupted_line_without_delimiter
    emailonly@gmail.com
    another.valid@sub2.example123.com|11:22:33:44:55:66:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:VGVzdFRva2VuMTIz
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
    assertTrue(not report:find("Z0bYjf"), "Report NEVER contains raw token")
    print(report)

    print(string.format("\n=========================================="))
    print(string.format("TEST RESULTS: %d PASSED, %d FAILED", passed, failed))
    print(string.format("=========================================="))

    if failed > 0 then
        os.exit(1)
    end
end

runTests()
