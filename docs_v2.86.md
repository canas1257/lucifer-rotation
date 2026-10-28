# Dokumentasi Lucifer v2.86 — Referensi Lua

Referensi berbahasa Indonesia untuk API **Nuron's Lucifer**, diperbarui dari
berkas lokal dalam folder [`update/`](update/).
Nama fungsi, properti, enum, serta kapitalisasi dipertahankan agar dapat dicocokkan dengan API aslinya.

## Sumber dan cakupan

Pembaruan ini menggunakan sumber lokal berikut, dengan **v2.86 sebagai acuan utama**:

| Sumber | Versi pada judul | Pemakaian |
| --- | --- | --- |
| [LUCIFER_LUA_V2_86.md](update/LUCIFER_LUA_V2_86.md) | 2.86 | Acuan utama API, perilaku, dan contoh baru. |
| [functions.md](update/functions.md) | 2.32 | Pembanding fungsi lama. |
| [enums.md](update/enums.md) | 2.32 | Pembanding enum lama. |
| [automations.md](update/automations.md) | 1.8 | Referensi historis automation. |
| [structs.md](update/structs.md) | 1.8 | Referensi historis struktur dan protokol. |

Dokumen awal merujuk [dokumentasi GitHub v1.8](https://github.com/NuronLucifer/Nurons-Lucifer/tree/main/docs),
termasuk `rotation.md` yang tidak ada di folder update. Informasi lama yang belum
dikonfirmasi ulang ditandai **Legacy / belum dikonfirmasi v2.86**; tidak disebutkan
di sumber baru bukan berarti sudah dihapus. Jika bertentangan, penjelasan v2.86 diutamakan.

Dokumen ini merupakan referensi gabungan, bukan salinan verbatim. Contoh Lua
**belum diuji di runtime Lucifer**. Signature yang tidak dirinci sumber tidak ditebak.

## Daftar isi

1. [Dasar penggunaan](#1-dasar-penggunaan)
2. [Fungsi global](#2-fungsi-global)
3. [Bot](#3-bot)
4. [World, tile, pemain, dan objek](#4-world-tile-pemain-dan-objek)
5. [Inventory dan informasi item](#5-inventory-dan-informasi-item)
6. [Console, Log, Credentials, Signal, dan Dialog](#6-console-log-credentials-signal-dan-dialog)
7. [Packet, vector, variant, dan RTVAR](#7-packet-vector-variant-dan-rtvar)
8. [HTTP, webhook, dan proxy](#8-http-webhook-dan-proxy)
9. [Enum](#9-enum)
10. [Automation](#10-automation)
11. [Rotation dan World Manager](#11-rotation-dan-world-manager)
12. [Contoh praktis](#12-contoh-praktis)
13. [Catatan ketidaksesuaian sumber](#13-catatan-ketidaksesuaian-sumber)
14. [Troubleshooting dan kompatibilitas](#14-troubleshooting-dan-kompatibilitas)

## 1. Dasar penggunaan

### Properti, metode, dan nilai kembalian

- Akses properti menggunakan titik: `bot.status`, `bot.auto_harvest.enabled`.
- Panggil metode instance menggunakan titik dua: `bot:getWorld()`, `bot:warp("WORLD")`.
- Panggil fungsi global langsung: `getBot()`, `sleep(1000)`.
- Konstruktor yang ditampilkan sumber menggunakan `.new()`, misalnya `HttpClient.new()`.
- `-> T` pada referensi menandakan tipe nilai kembalian, bukan sintaks Lua.
- *Read-only* berarti properti ditujukan untuk dibaca, bukan diubah.
- **R** berarti read-only dan **R/W** berarti dapat dibaca serta diubah.
- Array Lua pada referensi v2.86 menggunakan indeks awal **1**; gunakan `ipairs()`.
- `nil` menandakan tidak ada hasil. Periksa hasil lookup yang dapat mengembalikan `nil`.
- Metode aksi yang mengembalikan `nil` tidak melaporkan penerimaan server.
- Boolean pada request item seperti `fastDrop()` menunjukkan request lokal dapat
  dimulai, bukan jaminan server sudah menerima atau menyelesaikan aksi.

```lua
local bot = getBot()
if bot == nil then
    print("Script ini memerlukan konteks bot.")
    return
end

if bot.status == BotStatus.online then
    print("Bot online: " .. bot.name)
end

local target = getBot("NAMA_BOT")
if target then
    print(target.name)
end
```

### Waktu dan koordinat

Aturan umum v2.86: nilai waktu memakai **detik**, kecuali ditandai milidetik.
`sleep(ms)`, `getPing()`, dan argumen opsional `collect(range, interval_ms)`
memakai **milidetik**. `listenEvents(seconds)`, `getInterval(action)`, dan
`setInterval(action, seconds)` memakai **detik**.

Posisi `x`, `y` secara umum adalah koordinat **tile**, kecuali dinyatakan pixel.
`bot.x`, `bot.y` dan `PathNode.x`, `PathNode.y` memakai tile. `Player.posx`,
`Player.posy`, posisi `NetObject`, serta `World:isValidPosition(x, y)` memakai
**pixel**. Gunakan `World:isValidTile(x, y)` untuk batas tile.
`moveTo(dx, dy)` memakai selisih tile.

## 2. Fungsi global

### Waktu, item, dan file

| Fungsi | Keterangan |
| --- | --- |
| `sleep(ms: number)` | Menunda script selama sejumlah milidetik. |
| `getInfo(name: string)` / `getInfo(id: number) -> ItemDescription atau nil` | Mengambil informasi item berdasarkan nama atau ID. |
| `getInfos()` | Mengambil koleksi katalog item yang tersedia. |
| `read(path: string) -> string` | Membaca seluruh file; string kosong jika file tidak dapat dibuka. |
| `write(path: string, content: string) -> boolean` | Mengganti isi file. |
| `append(path: string, content: string) -> boolean` | Menambahkan isi ke akhir file. |
| `clearConsole() -> nil` | Membersihkan console aplikasi. |
| `removeColor(text: string) -> string` | Menghapus kode warna dari teks. |
| `getUsername() -> string` | Mengambil username akun Lucifer. |
| `getBanRate() -> number` | Mengambil nilai ban rate terakhir yang dilaporkan. |

```lua
local info = getInfo(4584)
if info ~= nil then
    print(info.name)
end
print(removeColor("`4Contoh nama"))

-- Gunakan path file di folder kerja yang diizinkan.
write("catatan-lucifer.txt", "Catatan script")
print(read("catatan-lucifer.txt"))
```

### Menambah, mengambil, dan menghapus bot

| Fungsi | Keterangan dari sumber |
| --- | --- |
| `addBot(name, password)` | Menambah bot dengan kredensial. |
| `addBot(name, mac, rid)` | Bentuk tiga argumen yang tetap dicantumkan v2.86; tipe akun tidak dirinci. |
| `addBot(name, password, mac, rid)` | Menambah bot dengan informasi perangkat. |
| `addBot(name, password, mac, rid, platform)` | Menambah bot dengan `Platform`. |
| `addBot(options)` | Menambah bot menggunakan tabel opsi. |
| `addUbiBot(email, password, otp_secret)` | Bentuk Ubi bot yang dicantumkan v2.86. |
| `addSteamBot(ubisoft_email, ubisoft_password, steam_login)` | Menambah Steam bot. |
| `addSteamBot(ubisoft_email, ubisoft_password, otp_secret, steam_login)` | Bentuk Steam dengan OTP secret. |
| `addTokenBot(token[, proxy])` | Menambah token bot, dengan proxy opsional. |
| `getBot() -> Lucifer atau nil` | Bot induk dalam script bot-local. |
| `getBot(name: string) -> Lucifer atau nil` | Lookup berdasarkan nama. |
| `getBot(index: number) -> Lucifer atau nil` | Lookup berdasarkan indeks awal 1. |
| `getBots() -> Lucifer[]` | Tabel seluruh bot, indeks awal 1. |
| `removeBot() -> nil` / `removeBot(name) -> nil` | Menghapus bot induk atau bot bernama. |

Nama tipe bot pada v2.86 adalah **`Lucifer`**. Tanda `[]` pada signature
menunjukkan argumen opsional atau array pada tipe return, bukan sintaks Lua.
Contoh sumber memperlihatkan hasil penambahan bot sebagai instance.

Opsi `addBot(options)` yang didukung: `name`, `display`, `password`, `mail`,
`mac`, `rid`, `vid`, `aid`, `secret`, `recovery`, `appleData`, `proxy`,
`steamlogin`, `gmaillogin`, `hash`, `platform`, dan `connect`.
Isi hanya field yang diperlukan untuk jenis akun tersebut.

```lua
local bot = addBot({
    name = "GROWID_ANDA",
    display = "Bot utama",
    password = "PASSWORD_ANDA",
    platform = Platform.windows,
    connect = false
})
if bot ~= nil then
    print(bot.name)
end
```

### Pack dan trash list

| Fungsi | Keterangan |
| --- | --- |
| `addPack(data) -> nil` / `removePack(data) -> nil` | Menambah/menghapus definisi pack; bentuk `data` tidak dirinci. |
| `getTrashList() -> integer[]` | Mengambil daftar global ID item yang ditandai untuk trash. |
| `setTrashList(ids) -> nil` | Mengganti seluruh daftar trash global. |

### Event

| Fungsi | Keterangan |
| --- | --- |
| `addEvent(type: Event, callback: function)` | Mendaftarkan callback untuk suatu jenis event. |
| `listenEvents(seconds: number)` | Mendengarkan event selama durasi tertentu. |
| `unlistenEvents()` | Menghentikan proses mendengarkan, termasuk dari callback. |
| `removeEvent(type: Event)` | Menghapus callback yang terdaftar untuk jenis event tersebut. |
| `removeEvents()` | Menghapus seluruh callback event yang terdaftar. |

```lua
local function onMessage(message)
    print(removeColor(message))
    if message:find("!stop", 1, true) then
        unlistenEvents()
    end
end

addEvent(Event.game_message, onMessage)
listenEvents(60)
removeEvent(Event.game_message)
```

### Manager, proxy, dan thread

| Fungsi | Keterangan |
| --- | --- |
| `getProxyManager() -> ProxyManager` | Mengambil pengelola proxy aplikasi. |
| `getWorldManager() -> WorldManager` | Mengambil pengelola world aplikasi. |
| `addProxy(proxy_data: string)` | Menambah proxy ke menu jika belum ada. |
| `getSwitchManager()` | Mengambil switch manager global. |
| `getProxies()` | Mengambil koleksi proxy. |
| `addDataProxy(proxy_data, is_http)` | Menambah data proxy. |
| `removeProxy(ip, port, username, password)` | Bentuk penghapusan proxy yang dicantumkan v2.86. |
| `runThread(callback: function, ...)` | Menjalankan fungsi di thread dengan argumen tambahan. |

```lua
local function report(label, count)
    for i = 1, count do
        print(label .. " " .. i)
        sleep(1000)
    end
end

runThread(report, "Thread", 3)
sleep(4000) -- Contoh menjaga script utama tetap aktif selama pekerjaan berjalan.
```

Setiap thread memiliki **Lua state sendiri**. Berikan argumen sederhana atau
objek API publik secara sengaja; penulisan bersama ke file atau pengaturan bot
memerlukan koordinasi.

### Lifecycle script

`script_id` adalah identifier script saat host menyediakannya.
Callback global opsional `on_stop(error_message)` dipanggil saat script selesai.
Pesannya kosong pada penyelesaian normal dan berisi error jika terjadi kegagalan.
`sleep()` tetap responsif terhadap permintaan stop.

```lua
function on_stop(error_message)
    if error_message ~= "" then
        print("Script berhenti: " .. error_message)
    end
end
```

### Shortcut global

Sumber mencantumkan shortcut berikut. Detail operasinya dapat dilihat pada
metode `World` dan `Bot` yang bersesuaian:

`getWorld`, `getInventory`, `getConsole`, `getLog`, `getLogin`, `getDialog`,
`getTile`, `getTilesSafe`, `getObject`, `getObjects`, `getPlayer`, `getPlayers`,
`getNPC`, `getNPCs`, `getLocal`, dan `hasAccess`.
Shortcut ini tersedia pada script **bot-local**. `getTiles` hanya dikonfirmasi
dalam referensi lama; gunakan `getTilesSafe()` untuk iterasi snapshot v2.86.

## 3. Bot

Instance `Lucifer` diperoleh dari `getBot()`; hasilnya dapat `nil` tanpa konteks bot.

### Properti identitas dan status

| Properti | Akses | Keterangan |
| --- | --- | --- |
| `name` | R | Nama bot. |
| `index` | R | Indeks awal 1; `-1` jika tidak tersedia. |
| `status` | R | Nilai `BotStatus`. |
| `custom_status` | R/W | Teks status buatan pengguna. |
| `google_status` | R | Nilai `GoogleStatus`. |
| `malady`, `home_world` | R | ID malady dan home world yang terdeteksi. |
| `selected` | R/W | Apakah bot dipilih pada menu. |
| `x`, `y` | R | Koordinat tile; keduanya `0` jika state pemain lokal tidak tersedia. |
| `history` | R | Riwayat generic message terbaru. |
| `warp_count` | R/W | Penghitung warp. |
| `gem_count`, `pearl_count` | R | Jumlah gems dan pearls saat ini. |
| `obtained_gem_count`, `obtained_pack_count` | R | Gems dan pack yang diperoleh selama run yang dilacak. |
| `level`, `is_account_secured` | R | Level dan status perlindungan akun terdeteksi. |
| `maximum_ping` | R/W | Batas ping yang dapat diterima. |

### Properti pengaturan

| Properti | Keterangan |
| --- | --- |
| `move_range` | Jarak antartile saat pathfinding. |
| `rest_time`, `rest_interval` | Lama istirahat dan interval antaristirahat. |
| `consume_id`, `consume_interval` | ID consumable dan interval pemakaian. |
| `reconnect_interval` | Interval reconnect. |
| `object_collect_delay` | Jeda pengambilan objek yang muncul. |
| `collect_range` | Jangkauan collect. |
| `collect_all` | Mode collect semua objek. |
| `collect_path_check` | Pemeriksaan jalur saat collect. |
| `ignore_gems`, `ignore_essences` | Mengabaikan gems atau essences. |
| `legit_mode` | Mengaktifkan/menonaktifkan legit mode. |

Pengaturan perilaku berikut writable. Atur sebelum mengaktifkan fitur terkait:

| Kelompok | Properti |
| --- | --- |
| Reconnect | `auto_reconnect`, `reconnect_multiplier`, `random_reconnect`, `reconnect_interval`, `min_reconnect`, `max_reconnect`, `bypass_logon`. |
| Stop dan ping | `auto_leave_on_admin`, `auto_leave_on_mod`, `auto_ban`, `auto_stop`, `maximum_ping`. |
| World | `leave_world_before_warp`, `legit_mode`, `auto_accept`, `auto_follow`, `anti_toxic`, `anti_fire`, `hide_gems`. |
| Inventory | `auto_trash`, `auto_wear`, `auto_clothes`, `auto_birth`, `auto_consume`, `auto_expand_inventory`, `wear_id`, `wear_storage`, `birth_storage`, `gem_limit`, `consume_id`, `consume_interval`. |
| Istirahat | `auto_rest_mode`, `auto_disconnect`, `disconnect_on_rest`, `rest_time`, `rest_interval`. |
| Collect | `auto_collect`, `collect_path_check`, `collect_all`, `object_collect_delay`, `collect_range`, `ignore_gems`, `ignore_essences`. |
| Gerakan | `move_range`, `move_x`, `move_y`, `dynamic_delay`. |
| Khusus | `auto_alien_scanner`, `auto_mooncake_magnificence`; `auto_tutorial` adalah objek module, bukan boolean. |

`auto_disconnect` dan `disconnect_on_rest` mengontrol pengaturan yang sama pada v2.86.
Instance automation dan `rotation` dijelaskan pada bagian 10–11.
Gunakan `getConsole()` dan `getLog()` untuk akses console/log.

### Informasi dan koneksi

| Metode | Keterangan |
| --- | --- |
| `getWorld() -> World` | World bot saat ini. |
| `getInventory() -> Inventory` | Inventory bot. |
| `getConsole() -> Console`, `getLog() -> Log` | Console dan log bot. |
| `getLogin() -> Credentials` | Objek kredensial; field publiknya tidak dirinci dalam v2.86. |
| `getProxy()` | Snapshot proxy bot. |
| `getPlaytime() -> integer`, `getAge() -> integer` | Waktu bermain dan umur akun; satuan khusus tidak dirinci. |
| `getActiveTime() -> string` | Waktu aktif bot dalam bentuk string. |
| `getPing() -> integer` | Ping dalam milidetik. |
| `getSignal() -> Signal` | Sinyal geiger terakhir. |
| `getCaptcha() -> string` | URL captcha atau string kosong. |
| `connect() -> nil` | Memulai koneksi; tidak mengembalikan hasil login. |
| `disconnect() -> nil` | Memutus koneksi bot. |
| `hasToken() -> boolean` | Memeriksa ketersediaan data token login. |
| `updateToken(token) -> nil` | Mengganti token login. |
| `updateProxy(proxy) -> boolean` | Mengubah proxy bot. |
| `setPlatform(platform) -> nil` | Mengatur platform login. |
| `isInWorld() -> boolean` | Apakah state world lengkap tersedia. |
| `isInWorld(name: string) -> boolean` | Apakah bot berada di world bernama tertentu. |
| `isInTile(x: number, y: number) -> boolean` | Apakah bot berada pada tile tertentu. |
| `isInTutorial() -> boolean` | Apakah world saat ini merupakan tutorial. |
| `isInArea(min_x, min_y, max_x, max_y) -> boolean` | Memeriksa posisi dalam persegi panjang tile. |
| `isSupporter() -> boolean` | Apakah status supporter terdeteksi. |
| `isResting() -> boolean` | Apakah bot beristirahat. |
| `isRunningScript() -> boolean` | Apakah executor bot menjalankan script. |

### World dan pergerakan

| Metode | Keterangan |
| --- | --- |
| `warp(name: string)` / `warp(name: string, id: string)` | Masuk world, dengan door ID opsional. |
| `leaveWorld()` | Keluar dari world. |
| `moveTo(difference_x: number, difference_y: number)` | Bergerak relatif; `(1, 0)` berarti ke kanan. |
| `moveTile(tilex: number, tiley: number)` | Bergerak ke tile jika posisi dan jangkauan valid. |
| `moveLeft()` / `moveLeft(range: number)` | Bergerak ke kiri. |
| `moveRight()` / `moveRight(range: number)` | Bergerak ke kanan. |
| `moveUp()` / `moveUp(range: number)` | Bergerak ke atas. |
| `moveDown()` / `moveDown(range: number)` | Bergerak ke bawah. |
| `enter()` / `enter(password: string)` / `enter(button_id: number)` | Mengaktifkan pintu; menyimpan password atau button ID jika diberikan. |
| `respawn()` | Respawn bot. |
| `getPath(x: number, y: number) -> table<PathNode>` | Mengambil jalur; tabel kosong jika jalur tidak ditemukan. |
| `findPath(x: number, y: number) -> boolean` | Mengikuti jalur dan menunggu sampai operasi selesai; **blocking**. |

Pilih tujuan valid dan jalur pendek untuk `findPath()`. Bentuk `findWorldPath()`
hanya tercantum pada referensi lama dan belum dikonfirmasi v2.86.

### Interaksi, item, dan collect

| Metode | Keterangan |
| --- | --- |
| `say(text: string)` | Mengirim pesan jika bot berada di world. |
| `use(item_id: number)` | Menggunakan consumable yang tersedia di inventory. |
| `activate(item_id: number)` | Alias `wear()`. |
| `wear(item_id: number)` / `unwear(item_id: number)` | Memakai/melepas item. |
| `drop(item_id: number, item_count: number)` | Menjatuhkan item dengan ID dan jumlah valid. |
| `trash(item_id: number, item_count: number)` | Membuang item dengan ID dan jumlah valid. |
| `fastDrop(item_id: number, item_count: number) -> boolean` | Mencoba memulai fast drop. |
| `fastTrash(item_id: number, item_count: number) -> boolean` | Mencoba memulai fast trash. |
| `buy(store_id: string)` | Membeli dari store berdasarkan store ID. |
| `buy(item_id: number, item_count: number, max_price: number) -> boolean` | Mencoba pembelian dengan batas harga. |
| `retrieve(x: number, y: number, count: number) -> boolean` | Mencoba mengambil hingga `count` item dari storage yang didukung. |
| `retrieve(x: number, y: number) -> boolean` | Mengambil jumlah default; v2.86 tidak merinci jumlahnya. |
| `active(x: number, y: number)` | Mengirim tile active packet. |
| `place(x: number, y: number, item: number)` | Meletakkan blok jika valid. |
| `hit(x: number, y: number)` | Memukul tile jika posisi dan jangkauan valid. |
| `hit(npc_id: number)` | Memukul NPC. |
| `wrench(x: number, y: number)` | Wrench tile jika posisi dan jangkauan valid. |
| `wrenchPlayer(netID: number)` | Wrench pemain jika ditemukan. |
| `collectObject(oid: number, range: number) -> boolean` | Mencoba mengambil satu objek. |
| `collectByID(item_id: number) -> boolean` | Mencari dan mencoba mengambil satu objek berdasarkan ID item. |
| `collect(range: number[, interval_ms: number]) -> nil` | Mencoba mengambil objek di sekitar dengan jeda dalam milidetik. |
| `findOutput([item_id]) -> boolean` | Mencari atau mendekati lokasi output yang dikonfigurasi. |

Metode aksi tanpa return eksplisit dalam tabel ini, seperti `drop()`, `place()`,
dan `say()`, mengembalikan `nil` pada v2.86. Konfirmasi efeknya dari state/event.

### Packet, tampilan, akun, dan script

| Metode | Keterangan |
| --- | --- |
| `sendRaw(packet)` | Mengirim raw packet; v2.86 tidak merinci formatnya. |
| `sendPacket(type: number, text: string)` | Mengirim packet teks untuk kompatibilitas script lanjutan. |
| `setBubble(bubble)` | Mengatur bubble; enum yang tersedia di sumber adalah `Bubble`. |
| `setSkin(id: number)` | Mengatur skin; batas 1–6 berasal dari referensi lama, bukan jaminan v2.86. |
| `setDirection(faceleft: boolean)` | `true` menghadap kiri, `false` ke kanan. |
| `setCountry(country: string)` | Mengubah kode negara dua huruf. |
| `setMac(mac: string)` / `setRid(rid: string)` | Mengubah MAC atau RID bot. |
| `updateBot([name[, password[, mac[, rid[, secret[, hash[, platform]]]]]]])` | Bentuk pembaruan akun dengan argumen opsional berurutan. |
| `updateCustomBot(options)` | Memperbarui akun melalui opsi. |
| `updateTokenBot(token[, proxy])` | Memperbarui token bot. |
| `updateUbiBot(email, password[, secret[, is_steam]])` | Memperbarui Ubi bot. |
| `runScript(content: string)` | Menjalankan isi script pada bot. |
| `stopScript()` | Menghentikan script bot yang berjalan. |

Ubah identitas/perangkat sebelum koneksi; perubahan saat online dapat membatalkan sesi.
Signature `updateBot(name, mac, rid)` lama tidak dijadikan acuan positional v2.86.

### Interval, role, dan pack

| Metode | Return | Keterangan |
| --- | --- | --- |
| `getInterval(action)` | `number` | Interval efektif dalam detik. |
| `setInterval(action, seconds)` | Tidak dirinci | Mengubah interval dasar. |
| `startRole(role)` | `boolean` | Memulai alur role. |
| `stopRole()` | `nil` | Menghentikan role. |
| `finishRole()` | `boolean` | Mencoba menyelesaikan role. |
| `getRoleMission()` | `string` | Meminta misi role saat ini. |
| `setPack(name)` | `nil` | Memilih pack terkonfigurasi berdasarkan nama. |
| `getMaladyDuration()` | Nilai durasi | Durasi tersisa malady yang dilacak; bentuk return tidak dirinci. |

```lua
local bot = getBot()
if bot == nil then return end
local previous = bot:getInterval(Action.move)
bot:setInterval(Action.move, 0.25)
print("Interval lama: " .. previous .. " detik")
```

## 4. World, tile, pemain, dan objek

### World

Ambil instance dengan `getBot():getWorld()` setelah bot dan state world tersedia.
Warp, reconnect, dan map update dapat mengganti state. Ambil ulang hasil query
setelah transisi; jangan mempertahankan objek world/tile lama untuk pekerjaan panjang.

| Properti | Keterangan |
| --- | --- |
| `name` | Nama world. |
| `x`, `y` | Lebar dan tinggi world. |
| `tile_count` | Jumlah tile. |
| `growscan` | Instance `Growscan`. |
| `weather` | ID cuaca. |
| `battle` | State battle; struktur detail tidak dirinci. |
| `public` | Apakah world bersifat publik. |
| `version` | Versi world. |

| Metode | Keterangan |
| --- | --- |
| `getTile(x: number, y: number) -> Tile atau nil` | Mengambil tile berdasarkan koordinat. |
| `getObject(oid: number) -> NetObject atau nil` | Mengambil objek berdasarkan object ID. |
| `getPlayer(netID: number \| string) -> Player` | Lookup berdasarkan netID atau nama; `nil` jika tidak ditemukan. |
| `getNPC(npcID: number) -> NPC` | Lookup NPC; `nil` jika tidak ditemukan. |
| `getAdventure(id: number) -> Adventure atau nil` | Mengambil marker adventure berdasarkan ID. |
| `getTilesSafe() -> table<Tile>` | Mengambil salinan tabel tile. |
| `getObjects() -> table<NetObject>` | Mengambil objek. |
| `getPlayers() -> table<Player>` | Mengambil pemain. |
| `getNPCs() -> table<NPC>` | Mengambil NPC. |
| `getAdventures() -> table<Adventure>` | Mengambil data adventure. |
| `getLocal() -> Player atau nil` | Mengambil pemain lokal milik bot. |
| `getTileParent(x: number, y: number) -> Tile atau nil` | Mengambil parent tile efektif pada koordinat. |
| `hasAccess(x: number, y: number)` | Mengembalikan nilai akses; v2.86 tidak menetapkannya sebagai boolean. |
| `hasAdventure(id: number) -> boolean` | Memeriksa keberadaan marker adventure. |
| `isValidTile(x: number, y: number) -> boolean` | Memeriksa batas koordinat tile. |
| `isValidPosition(x: number, y: number) -> boolean` | Memeriksa batas posisi pixel. |

Properti world di atas read-only. `getTilesSafe()`, `getObjects()`, `getPlayers()`,
dan `getNPCs()` menyediakan snapshot untuk iterasi. Raw collection seperti
`world.tiles` hanya ada di referensi lama; utamakan metode query v2.86.
Field `Adventure` belum dirinci oleh sumber baru.

### Tile dan TileExtra

Properti `Tile`: `foreground` (alias `fg`), `background` (alias `bg`), `x`, `y`,
`parent`, dan `flags`, semuanya read-only. `parent` merupakan indeks atau identifier parent tile.

| Metode | Keterangan |
| --- | --- |
| `hasExtra() -> boolean` | Memeriksa keberadaan data ekstra. |
| `getExtra() -> TileExtra` | Mengambil data ekstra; `nil` jika tidak ada. |
| `canHarvest() -> boolean` | Memeriksa apakah pohon siap dipanen. |
| `hasFlag(flag: number) -> boolean` | Memeriksa flag aktif pada tile. |

Metadata ekstra bergantung jenis tile. Nilai publik umum yang disebut v2.86:
`type`, `label`, `owner`, `locked`, `growth`, `item1`, `item2`, `item_count`,
`item_price`, `fruit_count`, dan `flags`. Panggil `hasExtra()` dahulu; field
yang tidak ada atau tidak relevan untuk tipe tile tidak boleh diasumsikan tersedia.

```lua
local bot = getBot()
if bot == nil or not bot:isInWorld() then return end
local tile = bot:getWorld():getTile(0, 0)
if tile ~= nil and tile:hasExtra() then
    local extra = tile:getExtra()
    if extra ~= nil and extra.label ~= nil then
        print(extra.label)
    end
end
```

### Player dan Clothes

| Properti Player | Keterangan |
| --- | --- |
| `name`, `altName`, `country` | Nama tampilan, nama alternatif, dan negara. |
| `netid`, `userid` | Network ID dan user ID. |
| `bubble` | Bubble pemain. |
| `posx`, `posy` | Posisi pemain dalam pixel. |
| `vecx`, `vecy` | Kecepatan pemain. |
| `team`, `battle_item`, `battle_score` | State battle pemain. |
| `isModerator`, `isSuperModerator` | Status moderator dan super moderator. |
| `isLocalPlayer` | Apakah pemain merupakan bot lokal. |
| `isFriendWithOwner` | Apakah pemain berteman dengan owner. |
| `skincolor`, `roleskin`, `roleicon` | Warna kulit, role skin, dan role icon. |
| `clothes` | Instance `Clothes`. |

`Clothes` memuat ID item pakaian: `hat`, `shirt`, `pants`, `shoes`, `face`,
`hand`, `wings`, `mask`, `neck`, `ances`. Nilai Player read-only.
`avatarFlags`, `flag2019`, `Clothes.unk1`, dan `Clothes.unk2` hanya tercantum
pada sumber lama, belum dikonfirmasi ulang dalam v2.86.

### NetObject, NPC, dan PathNode

| Struktur | Properti |
| --- | --- |
| `NetObject` | `id` (ID item), `x`, `y` (pixel), `count` (jumlah), `flags`, `oid` (object ID). |
| `NPC` | `type`, `id` (indeks world), `x`, `y`, `destx`, `desty` (tujuan), `var`, `unk`. |
| `PathNode` | `x`, `y` sebagai koordinat node jalur. |

Nilai ketiga struktur ini read-only. Makna spesifik `NPC.var` dan `NPC.unk`
tidak dijelaskan sumber.

### Growscan

v2.86 mengonfirmasi `World.growscan` sebagai hitungan agregat. Detail berikut
berasal dari referensi lama dan belum dirinci ulang pada v2.86:
properti `tiles` dan `objects` menyimpan pasangan **ID item → jumlah**.
Metode `getTiles()` dan `getObjects()` mengembalikan map tersebut.

```lua
local bot = getBot()
if bot ~= nil and bot:isInWorld() then
    local scan = bot:getWorld().growscan
    for id, count in pairs(scan:getObjects()) do
        local info = getInfo(id)
        print((info and info.name or tostring(id)) .. ": " .. count)
    end
end
```

## 5. Inventory dan informasi item

### Inventory

| Properti | Keterangan |
| --- | --- |
| `itemcount` | Jumlah entri inventory yang terisi, bukan total seluruh unit item. |
| `emptyslots` | Jumlah slot kosong. |
| `slotcount` | Kapasitas total slot. |
| `version` | Versi inventory. |

| Metode | Keterangan |
| --- | --- |
| `getItem(itemID: number \| string) -> InventoryItem` | Lookup item; `nil` jika tidak ditemukan. |
| `getItems() -> InventoryItem[]` | Mengambil snapshot item inventory. |
| `findItem(itemID: number \| string) -> number` | Mengambil jumlah item; `0` jika tidak ditemukan. |
| `getItemCount(itemID: number \| string) -> number` | Alternatif nama untuk operasi jumlah item menurut sumber. |
| `canCollect(itemID: number) -> boolean` | Memeriksa apakah item dapat diambil. |
| `price()` | Harga upgrade inventory berikutnya; bentuk nilai tidak dirinci. |

### InventoryItem

- `id`: ID item.
- `count`: jumlah item.
- `isActive`: apakah item sedang dipakai.

Ketiga nilai ini read-only. Gunakan `getItems()` alih-alih bergantung pada
raw property `items` dari referensi lama.

```lua
local bot = getBot()
if bot == nil then return end
local inventory = bot:getInventory()
local item = inventory:getItem(242)
if item then
    print("World Lock: " .. item.count)
end
print("Jumlah item 4584: " .. inventory:findItem(4584))
```

### ItemDescription

| Properti | Keterangan |
| --- | --- |
| `id`, `name` | ID unik dan nama item. |
| `desc` | Deskripsi item. |
| `flags`, `level`, `rarity` | Flag, level, dan rarity. |
| `growth`, `strength` | Nilai pertumbuhan dan kekuatan; interpretasi rinci tidak dijelaskan. |
| `action_type`, `collision_type`, `clothing_type` | Klasifikasi aksi, collision, dan pakaian. |
| `type`, `collision`, `clothing` | Nilai kategori tambahan. |
| `texture`, `visual` | Informasi tekstur dan visual. |

Semua nilai di atas read-only. `getInfo()` dapat menghasilkan `nil`.
Nama tipe lama adalah `ItemInfo`; jangan menganggap field lama seperti
`grow_time` identik dengan `growth`. Field lama lain dicatat pada bagian 13.

## 6. Console, Log, Credentials, Signal, dan Dialog

| Struktur | Properti | Metode |
| --- | --- | --- |
| `Console` | `enabled`, `contents`: tabel string isi console. | `append(text: string)`, `clear()` |
| `Log` | `content`: string isi tab log. | `append(text: string)`, `clear()` |
| `Credentials` | Field tidak dirinci pada panduan v2.86. | Diperoleh melalui `getLogin()`. |
| `Signal` | `x`, `y`: posisi tile; `type`: `GeigerArea`, read-only. | Tidak dicantumkan. |

```lua
local bot = getBot()
if bot == nil then return end
bot:getLog():append("Script dimulai")

for _, line in pairs(bot:getConsole().contents) do
    print(line)
end

local signal = bot:getSignal()
if signal.type ~= GeigerArea.null then
    print(string.format("Sinyal pada %i:%i", signal.x, signal.y))
end
```

**Legacy:** tipe `Login` dengan `mac` dan `rid` berasal dari sumber v1.8.
Panduan v2.86 menamai return `getLogin()` sebagai `Credentials` tanpa daftar field.

### Dialog dan DialogBuilder

Dalam script bot-local, `getDialog()` menyediakan helper dialog:

| Anggota | Keterangan |
| --- | --- |
| `active` | Mengatur apakah dialog normal ditampilkan. |
| `get()` | Mengambil dialog yang sudah di-parse saat ini. |
| `clear()` | Membersihkan state dialog saat ini. |
| `getCustom()` | Mengambil hasil custom dialog terakhir. |
| `setCustom(builder)` | Menampilkan custom dialog. |

`DialogBuilder` menyediakan `clear()`, `setTitle(text)`, `addLabel(text)`,
`addButton(name, label)`, `addCheckbox(name, label[, default])`, dan
`addInput(name, label[, default])`. Konstruktor dan bentuk hasil dialog tidak
dirinci pada sumber v2.86, sehingga tidak diasumsikan di sini.

## 7. Packet, vector, variant, dan RTVAR

**Legacy / belum dikonfirmasi rinci v2.86:** field, konstruktor, dan contoh
pada bagian ini berasal dari `update/structs.md` v1.8. v2.86 tetap menyebut
`sendPacket(type, text)`, `sendRaw(packet)`, serta objek packet/variant di callback,
tetapi sengaja tidak merinci format protokol. Keberadaan field di referensi lama
bukan jaminan kompatibilitas versi terbaru.

### GameUpdatePacket

Konstruktor: `GameUpdatePacket.new()`.

| Properti | Keterangan |
| --- | --- |
| `type`, `object_type` | Jenis packet dan perubahan objek. |
| `count1`, `count2` | Variabel jumlah, bergantung jenis packet. |
| `netid` | Network ID objek/pemain yang diperbarui. |
| `item` | Item yang diperbarui. |
| `flags` | Flag packet. |
| `float_var`, `int_data` | Data float dan integer yang maknanya bergantung packet. |
| `vec_x` / `pos_x`, `vec_y` / `pos_y` | Komponen posisi; sumber menampilkan kedua nama. |
| `vec2_x` / `pos2_x`, `vec2_y` / `pos2_y` | Komponen kecepatan; sumber menampilkan kedua nama. |
| `particle_rotation` | Rotasi partikel. |
| `int_x`, `int_y` | Variabel integer, misalnya posisi tile. |

Sumber tidak merinci nilai numerik jenis packet maupun kombinasi field yang
dibutuhkan untuk setiap jenisnya.

### Vector2 dan Vector3

- `Vector2`: properti `x`, `y`.
- `Vector3`: properti `x`, `y`, `z`.

Konstruktor kedua struktur ini tidak dijelaskan pada sumber.

### variant dan variantlist

Konstruktor yang diperlihatkan sumber: `variant.new()` dan `variantlist.new()`.

| Metode variant | Keterangan |
| --- | --- |
| `getType() -> VariantType` | Mengambil jenis nilai. |
| `print()` | Dump nilai menjadi string menurut deskripsi sumber. |
| `set(string)`, `set(int)`, `set(float)` | Mengisi nilai skalar. |
| `set(float, float)` / `set(float, float, float)` | Mengisi vector 2D/3D. |
| `set(vector2)` / `set(vector3)` | Mengisi dari instance vector. |
| `reset()` | Mengosongkan nilai. |
| `getString() -> string`, `getInt() -> number`, `getFloat() -> float` | Membaca nilai skalar. |
| `getVector2() -> Vector2`, `getVector3() -> Vector3` | Membaca nilai vector. |

`variantlist` menyediakan `get(index) -> variant` dan `print() -> string`.
Contoh sumber mengakses indeks `0`, sehingga jangan mengasumsikan indeks awal `1`.

```lua
local list = variantlist.new()
list:get(4):set("contoh")
if list:get(4):getType() == VariantType.string then
    print(list:get(4):getString())
end
```

### RTParam dan RTVAR

Properti `RTParam`: `parameters` (table), `key` (string), dan
`has_seperator` (boolean). Ejaan `seperator` mengikuti sumber.

| Metode RTVAR | Keterangan |
| --- | --- |
| `RTVAR.new()` / `RTVAR.new(text: string)` | Membuat objek kosong atau dari string parameter. |
| `params() -> string` | Mengambil daftar parameter sebagai string. |
| `append(key: string, value: string, separator: boolean)` | Menambah parameter string. |
| `append(key: string, value: number, separator: boolean)` | Menambah parameter angka. |
| `contains(key: string) -> boolean` | Memeriksa keberadaan key. |
| `dump() -> string` | Dump seluruh RTVAR menjadi string. |
| `erase(key: string)` | Menghapus parameter. |
| `find(key: string)` | Deskripsi sumber menyebut return RTParam atau `nil`, tetapi signature menyebut `number`. |
| `get(key: string) -> string` | Mengambil nilai string. |
| `getInt(key: string) -> number`, `getLong(key: string) -> number` | Mengambil nilai integer/long. |
| `getParam(key: string) -> rtparam` | Mengambil satu parameter. |
| `getParams(key: string) -> table` | Mengambil tabel parameter untuk key. |
| `modify(key: string, parameters: table, hasSeperator: boolean)` | Mengubah parameter. |
| `parse(str: string)` | Mem-parsing string dan memperbarui daftar parameter. |
| `size() -> number` | Mengambil jumlah parameter. |

```lua
local data = RTVAR.new()
data:append("action", "dialog_return", false)
data:append("dialog_name", "contoh", false)
data:append("x", 36, true)
print(data:dump())
```

## 8. HTTP, webhook, dan proxy

### HttpClient dan HttpResult

Konstruktor: `HttpClient.new()`.

| Properti HttpClient | Keterangan |
| --- | --- |
| `content` | Body request dalam bentuk string. |
| `method` | Metode HTTP; gunakan enum `Method` atau setter `setMethod()`. |
| `headers` | Tabel Lua header HTTP. |
| `url` | URL tujuan. |
| `timeout` | Timeout request, mengikuti satuan detik pada v2.86. |

| Metode | Keterangan |
| --- | --- |
| `setMethod(method: Method)` | Mengatur metode HTTP menggunakan enum. |
| `setProxy(type: Proxy, ...)` | Mengatur proxy request; bentuk argumen tambahan tidak dirinci. |
| `removeProxy()` | Menghapus proxy request. |
| `request() -> HttpResult` | Mengirim request. |

`HttpResult` berisi `body` (string), `error` (kode error jaringan, `0` jika tidak
ada error), dan `status` (kode status HTTP). Metode `getError()` memberikan
pesan error jaringan dalam bentuk string.
Properti HttpClient di atas writable; nilai HttpResult read-only.

```lua
local client = HttpClient.new()
client.url = "https://example.com"
client:setMethod(Method.get)
client.timeout = 10
client.headers = { ["User-Agent"] = "Lucifer" }

local result = client:request()
if result.error == 0 then
    print("HTTP " .. result.status)
    print(result.body)
else
    print(result:getError())
end
```

### Webhook dan Embed

Konstruktor yang diperlihatkan v2.86: `Webhook.new(url)`. Sumber lama juga
menyebut URL pesan, tetapi bentuk tersebut tidak dirinci ulang pada v2.86.

| Properti Webhook | Keterangan |
| --- | --- |
| `url`, `content` | URL webhook dan isi pesan. |
| `message_id` | ID pesan yang digunakan untuk pengeditan. |
| `username`, `avatar_url` | Nama pengirim dan URL avatar. |
| `embed1`, `embed2` | Embed pertama dan kedua. |

Metode: `makeContent() -> string` menghasilkan JSON gabungan pesan dan embed,
`send()` mengirim pesan, dan **`edit()`** mengedit pesan menggunakan state webhook.
v2.86 mencantumkan properti `message_id` dan metode tanpa argumen `edit()`;
bentuk `edit(message_id)` hanya berasal dari sumber lama.

Properti `Embed`:

- `use` (boolean), `color` (integer).
- `title`, `type`, `description`, `url`, `thumbnail`, `image`, serta `timestamp`.
- `footer.text`, `footer.icon_url`.
- `author.name`, `author.url`, `author.icon_url`.
- Metode `addField(name: string, value: string, inline: boolean)` menambah field.

```lua
-- Ganti placeholder dengan URL webhook milikmu sebelum menjalankan.
local bot = getBot()
if bot == nil then return end
local webhook = Webhook.new("URL_WEBHOOK_ANDA")
webhook.content = "Laporan bot"
webhook.embed1.use = true
webhook.embed1.title = "Status"
webhook.embed1.description = "Laporan dari script Lucifer"
webhook.embed1:addField("Bot", bot.name, true)
webhook:send()
```

### ProxyManager

Ambil instance dengan `getProxyManager()`.

- `proxies`: koleksi proxy yang dikelola.
- `localize`, `spread`: pengaturan Localize Country dan penyebaran proxy.
- `auto_switch`, `auto_check`, `switch_on_shadow`, `switch_on_ban`, `switch_on_block`.
- `cooldown`, `bypass_cooldown`, `timeout`.
- `main_ip_reference`: read-only.
- `addProxy`, `removeProxy`, `setLimit(new_limit)`: pengelolaan proxy/batas bot.

```lua
local manager = getProxyManager()
manager:setLimit(3)
manager:addProxy("127.0.0.1", 1080, "USER_ANDA", "PASSWORD_ANDA")
```

Snapshot proxy mempunyai `ip`, `port`, `username`, dan `password` read-only.
Managed proxy juga memiliki `cooldown`, `country`, `reference`, `selected`,
`setCooldown()`, `removeCooldown()`, dan `hasCooldown()`.
Bentuk satu string `addProxy(proxy_data)` berasal dari sumber lama; contoh
manager v2.86 menggunakan empat argumen. Global `addProxy(proxy_data)` tetap
dicantumkan dalam v2.86.

### HTTP server

Konteks scripting utama **dapat** menyediakan `HttpServer`, `HttpRequest`, dan
`HttpResponse`. Sumber tidak menyatakan bahwa ini tersedia di semua script bot-local.

| API | Keterangan |
| --- | --- |
| Server `get`, `post`, `put`, `delete`, `patch` | Mendaftarkan handler request. Signature registrasi tidak dirinci. |
| `setLogger` | Mengatur logger. |
| `listen(ip, port)` | Mendengarkan pada interface dan port; hanya satu server dapat listen pada satu waktu. |
| Handler `(request, response)` | Parameter callback request. |
| `request:getHeader(name)` | Lookup header request. |
| `request:getParam(name)` | Lookup parameter request. |
| `response.status`, `response.body` | Mengatur status dan body response. |
| Header response / `response:setContent(body, content_type)` | Mengatur header atau content response. |

Konstruktor server dan bentuk field header tidak dijelaskan sumber; contoh
inisialisasi lengkap tidak dibuat berdasarkan asumsi.

## 9. Enum

Gunakan nama enum, misalnya `BotStatus.online`, bukan menebak nilai numeriknya.
Nilai numerik enum tidak dicantumkan dalam sumber.

### BotStatus

| Nilai | Arti |
| --- | --- |
| `offline`, `online` | Bot offline atau online. |
| `wrong_password` | Password salah. |
| `account_banned`, `location_banned` | Akun atau lokasi perangkat terkena ban. |
| `version_update` | Versi game perlu diperbarui. |
| `advanced_account_protection` | Perlindungan akun mencegah login. |
| `server_overload`, `server_busy` | Server kelebihan beban atau sibuk. |
| `too_many_login` | Terlalu banyak percobaan login. |
| `maintenance` | Server maintenance. |
| `guest_limit` | Batas guest pada IP tercapai. |
| `http_block` | Koneksi HTTP dari IP bot diblokir. |
| `bad_name_length` | Nama terlalu pendek atau panjang. |
| `invalid_account` | Akun tidak valid. |
| `error_connecting`, `logon_fail` | Koneksi atau login gagal. |
| `captcha_requested` | Server meminta captcha. |
| `mod_entered` | Moderator memasuki world bot. |
| `high_load` | Subserver bot sedang mengalami beban tinggi. |
| `getting_server_data`, `retrieving_token`, `changing_subserver` | Mengambil data server, mengambil token, atau berpindah subserver. |
| `stopped` | Aksi bot dihentikan. |
| `account_suspended`, `ubi_disabled` | Akun ditangguhkan atau Ubi dinonaktifkan. |
| `account_restricted`, `network_restricted` | Pembatasan akun atau jaringan. |
| `could_not_warp`, `bad_inventory` | Gagal warp atau inventory bermasalah. |
| `bad_gateway`, `server_issue` | Masalah gateway atau server. |
| `two_factor` | Status autentikasi dua faktor. |
| `google_logon_fail`, `steam_logon_fail`, `steam_not_linked` | Masalah login Google/Steam atau akun Steam belum ditautkan. |
| `failed_captcha`, `banwave_detected`, `sms_error` | Captcha gagal, banwave terdeteksi, atau SMS error. |
| `player_entered`, `high_ping` | Pemain masuk atau ping tinggi. |
| `bypassing_server_data`, `linking_steam`, `solving_captcha` | Proses bypass data server, penautan Steam, atau penyelesaian captcha. |

### CaptchaStatus

**Legacy:** enum berikut dan `bot.captcha_status` tercantum dalam v2.32/v1.8,
tetapi tidak dikonfirmasi ulang oleh panduan v2.86. Jangan menyamakannya dengan `GoogleStatus`.

| Nilai | Arti |
| --- | --- |
| `no_captcha` | Tidak ada captcha. |
| `not_found` | Captcha tidak ditemukan. |
| `solved`, `solving` | Selesai atau sedang diselesaikan. |
| `wrong`, `failed` | Jawaban salah atau penyelesaian gagal. |
| `no_access` | Akses gagal karena HTTP forbidden atau bad gateway. |
| `invalid_key` | API key captcha salah. |
| `invalid_token` | Token tidak valid; sumber mengaitkannya dengan website yang bermasalah. |

### Event

| Nilai | Parameter callback |
| --- | --- |
| `variantlist` | `function(variantlist, netid)` |
| `game_message` | `function(message)` |
| `generic_text` | `function(message)` |
| `update_packet` | `function(packet)` |
| `track_packet` | `function(message)` |
| `mod_enter` | `function(text)` |
| `got_punched` | `function(text)` |
| `render` | `function()` |

Callback sebaiknya singkat. Salin atau antrekan data yang diperlukan lalu kembali;
proses panjang di callback dapat menunda penghentian script.

### GoogleStatus

Nilai `bot.google_status` yang dicantumkan v2.86:

`idle`, `processing`, `bad_server`, `bad_connection`, `invalid_key`,
`missing_server`, `missing_local_server`, `timeout`, `driver_closed`, `init_error`,
`invalid_credentials`, `invalid_secret`, `account_disabled`, `captcha_required`,
`phone_required`, `recovery_required`, `otp_required`, `invalid_challenge`,
`couldnt_verify`, `unknown_url`, `redirect`.

### Enum lainnya

| Enum | Nilai |
| --- | --- |
| `Method` | `get`, `post`, `put`, `patch`, `delete`, `head`. |
| `Platform` | `windows`, `android`, `macos`, `ios`, `ubiconnect`, `steam`, `apple`. |
| `Action` | `move`, `collect`, `hit`, `place`, `harvest`, `plant`, `warp`, `drop`, `trash`. |
| `VariantType` (legacy) | `float`, `int32`, `uint32`, `string`, `unused`, `vector2`, `vector3`, `component`, `entity`. |
| `GeigerArea` | `null` (tidak ada), `red`, `yellow`, `green`, `rapid` (rapid green), `prize`. |
| `Role` | `farm` (Farmer), `build` (Builder), `surg` (Master Surgeon), `fish` (Fisher), `cook` (Chef), `startopia` (Star Captain). |
| `Bubble` | `none`, `talk`, `brb`. |
| `StorageType` | `pack`, `seed`. |
| `Proxy` | `none`, `http`, `https`, `socks5`. |

`PlayerState`, `TileType`, `TileFlag`, dan `NpcType` hanya memiliki judul bagian
di sumber; daftar nilai dan cara penggunaannya belum disediakan.
`BotStatus.guest_disabled` ada pada v2.32, tetapi tidak dicantumkan ulang pada
daftar v2.86. `ubi_disabled` adalah nama yang tercantum v2.86; sumber tidak
menyatakan keduanya alias.

## 10. Automation

Semua instance berikut diakses melalui properti bot. Konfigurasikan module
terlebih dahulu, lalu ubah `enabled` atau panggil metode start yang sesuai.
Tidak setiap module cocok untuk setiap world atau state akun.

### Referensi module v2.86

Tabel ini mengikuti daftar anggota publik v2.86. Nama metode yang hanya disebut
tanpa signature tidak diberi argumen tambahan berdasarkan tebakan.

| Properti bot / tipe | Pengaturan dan metode publik |
| --- | --- |
| `auto_tutorial` / `AutoTutorial` | `enabled`, `set_high_level`, `set_random_skin`, `set_random_profile`, `detect_tutorial`, `clear_inventory`; read-only `world`, `message`. |
| `auto_farm` / `AutoFarm` | `enabled`, `auto_place`, `auto_break`, `auto_retrieve`, `auto_remote`, `mag_x`, `mag_y`, `id`, `block_storage`, `seed_storage`, `setActive(state)`. |
| `auto_spam` / `AutoSpam` | `enabled`, `show_emote`, `use_color`, `random_interval`, `auto_interval`, `randomizer`, `interval`, `messages`. |
| `auto_message` / `AutoMessage` | `enabled`, `type`, `ignore_admin`, `auto_sb`, `loop_mode`, `interval`, `victim_uid`, `anti_exit`, `message`; metode `load`, `save`, `clear`, `start`. |
| `auto_geiger` / `AutoGeiger` | `enabled`, `use_chocolate`, `insta_path`; metode `addWorld`, `removeWorld`, `addStorage`, `removeStorage`, `spread`. |
| `auto_fish` / `AutoFish` | `enabled`, `auto_trash`, `auto_drill`, `auto_trawler`, `auto_gemonade`, `x`, `y`, `world`, `item_storage`, `reward_storage`; metode `setRod`, `setBait`, `getRod`, `getBait`. |
| `auto_cook` / `AutoCook` | `is_cooking`, `x`, `y`, `interval`, `world`, `ingredient_storage`, `food_storage`; metode `setActive`, `setFood`, `setTemperature`, `start`, `stop`. |
| `auto_crime` / `AutoCrime` | `enabled`, `auto_wave`, `auto_bbq`, `world`, `tool_storage`, `reward_storage`; metode `setActive`. |
| `auto_carnival` / `AutoCarnival` | `enabled`, `auto_trash`, `auto_buy`, `selected_game`, `reward_storage`, `ticket_storage`. |
| `auto_parkour` / `AutoParkour` | `enabled`, `type`, `limit`, `block`; metode `setWebhook`, `setTicket`, `setReward`. |
| `auto_synth` / `AutoSynth` | `enabled`, `x`, `y`, `world`, `tool_storage`, `reward_storage`. |
| `auto_npc` / `AutoNPC` | `enabled`, `auto_spawner`, `auto_sucker`, `collect_mode`, `spawner_limit`, `sucker_limit`, `main_world`, `item_storage`, `reward_storage`. |
| `auto_transfer` / `AutoTransfer` | `enabled`, `drop_vertical`, `restock_vend`, `auto_vend`, `itemid`, `set_price`, `buy_price`, `per_item`, `input`, `output`. |
| `auto_harvest` / `AutoHarvest` | `enabled`, `recycle`, `useFuel`, `storage`, `loop`, `add(world)`, `remove(world)`. |
| `auto_plant` / `AutoPlant` | `enabled`, `storage`, `loop`, `add(world)`, `remove(world)`. |
| `auto_event` / `AutoEvent` | `enabled`, `storage`. |
| `auto_skin` / `AutoSkin` | `enabled`, `interval`. |
| `auto_blarney` / `AutoBlarney` | `enabled`, `storage`; read-only `index`, `state`, `console`. |
| `auto_set_pos` / `AutoSetPosition` | `enabled`, `warp_delay`, `move_delay`, `world`. |
| `auto_clear` / `AutoClear` | `enabled`, `name_length`, `keep_jammer`, `keep_lock`, `no_number`, `output_path`, `item_storage`, `seed_storage`. |
| `auto_build` / `AutoBuild` | `enabled`, opsi build, nama storage, output path, ID item terpilih; read-only `console`. Nama field selain `enabled` dan `console` tidak dirinci. |
| `auto_malady` / `AutoMalady` | `enabled`, opsi pengobatan, `disconnect_interval`, `storage`, `vial`; metode `addHospital`, `removeHospital`. Nama field opsi pengobatan tidak dirinci. |
| `auto_zombie` / `AutoZombie` | `enabled`, `infect_mode`, `punch_mode`, `punch_door`, `cell_limit`, `zombie_world`, `gvirus_storage`, `reward_storage`. |
| `auto_fossil` / `AutoFossil` | `enabled`, `loop_mode`, `use_rock`, `interval`, `tool_storage`, `fossil_storage`. |
| `auto_combine` / `AutoCombine` | `enabled`, `output_id`, `world`, `ingredient_storage`, `output_world`, `setIngredient(index, id, count)`. |
| `rotation` / `Rotation` | Lihat bagian 11; sumber hanya merinci sebagian nama field. |

### Perubahan automation yang memengaruhi script lama

- `auto_tutorial` berupa objek: gunakan `bot.auto_tutorial.enabled`, bukan menimpa objek dengan boolean.
- AutoFarm v2.86 mencantumkan **`setActive(state)`**, berbeda dari bentuk dua
  argumen `setActive(index, active)` pada v1.8. Bentuk/rincian `state` tidak dijelaskan;
  contoh loop indeks lama tidak dijadikan contoh v2.86.
- AutoSpam mencantumkan `messages`; bentuk koleksi ini tidak dijelaskan.
  `setText(index, text)` hanya dikonfirmasi sumber lama.
- AutoGeiger tidak mengonfirmasi ulang `afk`; AutoFish tidak mengonfirmasi ulang `auto_rod`.
- AutoHarvest/AutoPlant mencantumkan properti **`storage`**, bukan `setStorage()`.
- AutoParkour **`setReward` sudah dicantumkan eksplisit** pada v2.86.

### Contoh pengaturan AutoFish v2.86

```lua
local bot = getBot()
if bot == nil then return end
local fish = bot.auto_fish
fish.world = "FISHINGWORLD"
fish.item_storage = "BAITSTORAGE"
fish.reward_storage = "REWARDSTORAGE"
fish:setRod(3040) -- Ganti dengan ID joran yang sesuai.
fish:setBait(5526) -- Ganti dengan ID umpan yang sesuai.
fish.enabled = true
```

### Konfigurasi harvest dan plant

Anggota v2.86 yang dikonfirmasi:

```lua
local bot = getBot()
if bot == nil then return end
local harvest = bot.auto_harvest
harvest.enabled = false
harvest.storage = "STORAGE_ANDA"

local plant = bot.auto_plant
plant.enabled = false
plant.storage = "STORAGE_ANDA"
```

Contoh ini hanya menyiapkan storage; tambahkan world melalui `add(world)` dan
aktifkan setelah konfigurasi sesuai aplikasi. v2.86 tidak menjelaskan grammar
string `world` atau `storage`, tipe/nilai `loop`, maupun rincian `useFuel` dan
`recycle`. Format lama `WORLD:ID:ITEM_ID` dan `STORAGE|ID` di bawah adalah
referensi historis, **bukan format yang sudah dikonfirmasi v2.86**.

### Rincian historis v1.8

**Semua subbagian di bawah sampai akhir bagian 10 adalah legacy.** Detail indeks,
format, enum numerik module, dan signature tambahan berasal dari
`update/automations.md` v1.8. Gunakan tabel v2.86 di atas jika berbeda.

### AutoSpam — `auto_spam`

| Properti/metode | Keterangan |
| --- | --- |
| `enabled` | Mengaktifkan fitur. |
| `interval` | Interval antarpesan; satuan tidak dijelaskan sumber. |
| `random_interval` | Menggunakan interval acak. |
| `show_emote` | Menampilkan emote saat auto-spam. |
| `setText(index: number, message: string)` | Mengatur teks pada indeks **0–3**. |

### AutoGeiger — `auto_geiger`

- `enabled`: mengaktifkan fitur.
- `afk`: memaksa bot berada di main door.

### AutoMessage — `auto_message`

| Properti/metode | Keterangan |
| --- | --- |
| `enabled` | Mengaktifkan fitur. |
| `type` | `0`: Message; `1`: UID Message; `2`: List Message; `3`: Single Message. |
| `ignore_admin` | Mengabaikan admin saat messaging. |
| `auto_sb` | Mengarahkan bot ke world SB. |
| `loop_mode` | Mode loop; sumber merujuk penjelasan tanda `?` di menu. |
| `uid_count` | Jumlah UID terkumpul; disebut read-only pada entri pertama sumber. |
| `messaging` | Read-only; apakah sedang messaging pada List Message. |
| `message` | Teks pesan. |
| `start()` | Memulai messaging. |
| `load()` / `save()` | Memuat/menyimpan daftar UID dari/ke file. |
| `clear()` | Menghapus file daftar UID dan UID yang terkumpul. |

### AutoFish — `auto_fish`

Properti boolean: `enabled`, `auto_rod`, `auto_trash`, `auto_drill`.
Metode: `setRod(id: number)` memilih joran dan `setBait(id: number)` memilih umpan.

### AutoFarm — `auto_farm`

- `enabled`: mengaktifkan fitur.
- `speed`: kecepatan farming; satuan tidak dijelaskan.
- `id`: ID item farming.
- `auto_break`, `auto_place`: mengaktifkan break/place.
- `setActive(index: number, active: boolean)`: mengaktifkan posisi berdasarkan indeks menu.

```lua
-- Contoh legacy v1.8; bukan signature setActive v2.86.
local bot = getBot()
if bot == nil then return end
local farm = bot.auto_farm
farm.id = 4584
farm.speed = 100
farm.auto_place = true
farm.auto_break = true
for i = 0, 4 do
    farm:setActive(i, true)
end
farm.enabled = true
```

### AutoCrime — `auto_crime`

`enabled` mengaktifkan fitur. `setActive(index: number, active: boolean)`
mengatur pilihan villain berdasarkan indeks menu. Contoh sumber memakai indeks `0`.

### AutoCook — `auto_cook`

| Properti/metode | Keterangan |
| --- | --- |
| `is_cooking` | Apakah bot sedang memasak. |
| `interval` | Interval antarpacket. |
| `setActive(index: number, active: boolean)` | Mengatur tile terpilih pada menu. |
| `setFood(index: number)` | Memilih makanan pada indeks **0–33**. |
| `setTemperature(level: number)` | `0`: low; `1`: medium; `2`: high. |
| `start()` / `stop()` | Memulai/menghentikan memasak. |

```lua
-- Rentang indeks dan pemetaan suhu dari referensi v1.8.
local bot = getBot()
if bot == nil then return end
local cook = bot.auto_cook
for i = 0, 63 do
    cook:setActive(i, true)
end
cook:setFood(0) -- Berry Crepes menurut contoh sumber.
cook:setTemperature(1) -- Medium menurut definisi metode.
cook:start()

while cook.is_cooking do
    sleep(1000)
end
```

### AutoCarnival — `auto_carnival`

Properti `enabled`, `auto_trash`, dan `auto_buy` mengaktifkan fitur masing-masing.
`selected_game` menentukan indeks game pada menu; contoh sumber memakai `1`
untuk game kedua.

### AutoParkour — `auto_parkour`

- `enabled`: mengaktifkan fitur.
- `type`: `0` wolf, `1` fenrir, `2` clash.
- `limit`: batas tiket yang digunakan.
- `setWebhook(webhook_link: string)`: mengatur URL webhook.
- `setTicket(world_with_id: string)`: storage tiket; **huruf kapital**, format `NAME|ID`.
- `setReward(world_with_id: string)` untuk storage reward salah ditulis sebagai
  `setWebhook` pada daftar lama. **Nama metode `setReward` sudah dikonfirmasi v2.86**;
  aturan format `NAME|ID` tetap berasal dari v1.8.

### AutoTransfer — `auto_transfer`

| Properti | Keterangan |
| --- | --- |
| `enabled`, `drop_vertical` | Mengaktifkan transfer dan drop vertikal. |
| `auto_vend`, `restock_vend` | Mengaktifkan auto-vend dan restock vending. |
| `set_price`, `buy_price` | Harga jual yang diatur pada vend dan harga beli. |
| `per_item` | Metode pembelian item; tipe/nilai tidak dirinci sumber. |
| `itemid` | ID item yang ditransfer. |

```lua
local bot = getBot()
if bot == nil then return end
local transfer = bot.auto_transfer
transfer.itemid = 4584
transfer.drop_vertical = true
transfer.restock_vend = true
transfer.enabled = true
```

### AutoHarvest — `auto_harvest`

- `enabled`: mengaktifkan auto-harvest.
- `add(format: string)`: menambah world.
- `remove(name: string)`: menghapus world.
- `setStorage(name_and_id: string)`: mengatur storage.

Format yang diperlihatkan contoh sumber:

- World: `NAMA_WORLD:DOOR_ID:ITEM_ID`.
- Storage: `NAMA_STORAGE|DOOR_ID`.

```lua
-- Contoh legacy v1.8; v2.86 mencantumkan properti storage.
local bot = getBot()
if bot == nil then return end
local harvest = bot.auto_harvest
harvest:setStorage("STORAGE|123")
harvest:add("FARM:ID:4585")
harvest.enabled = true
```

### AutoPlant — `auto_plant`

API yang dicantumkan sama bentuknya dengan AutoHarvest:
`enabled`, `add(format: string)`, `remove(name: string)`, dan
`setStorage(name_and_id: string)`.

```lua
-- Contoh legacy v1.8; v2.86 mencantumkan properti storage.
local bot = getBot()
if bot == nil then return end
local plant = bot.auto_plant
plant:setStorage("STORAGE|123")
plant:add("FARM:ID:4585")
plant.enabled = true
```

Format di atas berasal dari contoh sumber. Aturan escaping separator dan door ID
kosong tidak dijelaskan sumber.

## 11. Rotation dan World Manager

### Acuan v2.86

`bot.rotation` menyediakan `enabled` dan `status`. Sumber juga menyebut opsi
rest/fill/fossil/exchange, suppression storage, posisi break, ID item, dan custom
tile **tanpa daftar lengkap nama field atau signature**. Nama field historis
di bawah tidak otomatis menjadi kontrak v2.86.

`getWorldManager()` mengembalikan pengelola world rotation global:

| Metode v2.86 | Keterangan |
| --- | --- |
| `addFarm(name)` / `removeFarm(name)` | Menambah/menghapus farm; bentuk baru hanya mencantumkan argumen nama. |
| `addStorage(...)` / `removeStorage(name, storage_type)` | Mengelola storage; argumen penambahan belum dirinci. |
| `selectAll()` / `unselectAll()` | Mengatur pilihan semua world. |
| `selectFarm(name)` / `unselectFarm(name)` | Mengatur pilihan farm. |
| `selectStorage(...)` / `unselectStorage(...)` | Mengatur pilihan storage; overload tidak dirinci. |
| `getRandomStorage(...)` | Mengambil storage acak; argumen/return belum dirinci. |

Gunakan `StorageType.pack` atau `StorageType.seed` saat tipe storage diperlukan.
`assign*` dan `apply*` dari v1.8 tidak dicantumkan ulang dalam panduan v2.86.
Pengaturan interval yang jelas tersedia pada v2.86 adalah
`bot:setInterval(Action.harvest, seconds)` dan aksi terkait, bukan menebak
lokasi properti interval lama.

### SwitchManager v2.86

`getSwitchManager()` mengembalikan manager switch global. Metodenya:
`addBot`, `removeBot([name])`, `switch()`, dan `exists(name)`.
Signature `addBot` tidak dirinci oleh sumber.

Pengaturan mencakup pemicu switch otomatis, perilaku istirahat, loop mode,
batas, storage, dan **`drop_on_switch`**. Selain `drop_on_switch`, nama field
konkret pengaturan tersebut tidak diberikan sehingga tidak ditebak di sini.

### Referensi historis rotation v1.8

**Seluruh tabel dan contoh berikut sampai akhir bagian 11 adalah legacy.**
Sumbernya adalah `rotation.md` upstream yang dipakai pada dokumentasi awal,
bukan berkas v2.86 lokal.

### Rotation — `getBot().rotation`

| Properti | Keterangan |
| --- | --- |
| `enabled` | Mengaktifkan rotation. |
| `anti_fire`, `anti_toxic`, `take_fossil` | Fitur yang ditandai **Not Implemented** pada contoh sumber. |
| `auto_fill` | Mengaktifkan Auto Fill. |
| `dynamic_delay` | Mengaktifkan dynamic delay. |
| `gem_limit`, `world_limit` | Batas gems dan jumlah farm. |
| `id` | Contoh mengisinya dengan ID item `4584`; deskripsi sumber salah menyebut Anti Fire. |
| `pack` | Indeks pack terpilih pada menu. |
| `harvest_interval`, `plant_interval`, `break_interval`, `warp_interval` | Interval aktivitas; lokasi propertinya bertentangan antara daftar dan contoh sumber. |
| `seed_storage`, `pack_storage` | Nama storage, string read-only. |
| `farms` | Tabel string world rotation, read-only. |
| `index` | Indeks world rotation saat ini, read-only. |

Daftar properti sumber menempatkan interval pada `rotation`, tetapi contohnya
menulis `getBot().harvest_interval`, `getBot().break_interval`,
`getBot().plant_interval`, dan `getBot().warp_interval`. Verifikasi lokasi dan
satuannya pada versi aplikasi sebelum memakai pengaturan interval tersebut.

```lua
-- Contoh legacy v1.8.
local bot = getBot()
if bot == nil then return end
local rotation = bot.rotation
rotation.gem_limit = 2000
rotation.world_limit = 9
rotation.id = 4584
rotation.pack = 0
rotation.dynamic_delay = true
-- Aktifkan setelah world dan storage sudah ditetapkan.
```

### WorldManager

Pengelola world bersifat global untuk aplikasi. Ambil melalui `getWorldManager()`.
Format nama dan door ID pada contoh WorldManager menggunakan **titik dua**:
`WORLD:ID`, berbeda dari storage automation yang menggunakan `WORLD|ID`.

| Metode | Keterangan |
| --- | --- |
| `addFarm(name_and_id: string, item_id: number)` | Menambah farm rotation. |
| `removeFarm(name: string)` | Menghapus farm jika ada. |
| `addStorage(name_and_id: string, type: StorageType, seed_id: number)` | Menambah storage; untuk pack gunakan `0` pada argumen terakhir. |
| `removeStorage(name: string, type: StorageType)` | Menghapus storage jika ada. |
| `assign()` | Membagikan farm dan storage ke bot. |
| `assignFarm()` / `assignStorage()` | Membagikan farm/storage saja. |
| `apply(bot: Bot)` | Menerapkan farm dan storage terpilih ke bot tertentu. |
| `applyFarm(bot: Bot)` / `applyStorage(bot: Bot)` | Menerapkan pilihan farm/storage saja. |
| `selectAll()` / `unselectAll()` | Memilih/membatalkan pilihan semua farm dan storage. |
| `selectFarm(name: string)` / `unselectFarm(name: string)` | Mengatur pilihan farm. |
| `selectStorage(name: string, type: StorageType)` | Memilih storage. |
| `unselectStorage(name: string, type: StorageType)` | Membatalkan pilihan storage. |

Nama parameter terakhir `addStorage` adalah `seed_id` pada signature, tetapi
contoh sumber mengisi `4584` untuk storage seed. Sumber tidak menjelaskan
lebih lanjut hubungan ID blok/seed untuk parameter tersebut.

```lua
-- Contoh legacy v1.8; addFarm/assign/apply belum dikonfirmasi dalam bentuk ini di v2.86.
local bot = getBot()
if bot == nil then return end
local manager = getWorldManager()

manager:addFarm("FARM:ID", 4584)
manager:addStorage("SEEDSTORAGE:123", StorageType.seed, 4584)
manager:addStorage("PACKSTORAGE:123", StorageType.pack, 0)

manager:unselectAll()
manager:selectFarm("FARM")
manager:selectStorage("SEEDSTORAGE", StorageType.seed)
manager:selectStorage("PACKSTORAGE", StorageType.pack)
manager:apply(bot)

bot.rotation.id = 4584
bot.rotation.enabled = true
```

## 12. Contoh praktis

Contoh di bawah merupakan ilustrasi API. Ganti nama world, door ID, dan parameter
sesuai kebutuhan sebelum menjalankan.

### Masuk world dengan batas waktu tunggu

```lua
local bot = getBot()
local worldName = "WORLD_ANDA"
if bot == nil then return end

if bot.status == BotStatus.online then
    bot:warp(worldName, "DOOR_ID")

    local entered = false
    for attempt = 1, 30 do
        if bot:isInWorld(worldName) then
            entered = true
            break
        end
        sleep(1000)
    end

    if entered then
        print("Berada di " .. bot:getWorld().name)
    else
        print("World belum dimasuki setelah batas waktu tunggu.")
    end
else
    print("Bot belum online.")
end
```

### Mencari pohon siap panen tanpa memukul tile

```lua
local bot = getBot()
if bot ~= nil and bot:isInWorld() then
    for _, tile in ipairs(bot:getWorld():getTilesSafe()) do
        if tile:canHarvest() then
            print(string.format("Siap panen pada (%i, %i)", tile.x, tile.y))
        end
    end
end
```

### Membaca seluruh inventory

```lua
local bot = getBot()
if bot == nil then return end
local inventory = bot:getInventory()
for _, item in ipairs(inventory:getItems()) do
    local info = getInfo(item.id)
    local name = info and info.name or "Item tidak ada di katalog"
    print(string.format("%s [ID %i]: %i", name, item.id, item.count))
end
```

### Memeriksa jalur dan bergerak ke tujuan

```lua
local bot = getBot()
if bot == nil or not bot:isInWorld() then return end
local world = bot:getWorld()
local x, y = 50, 30
if not world:isValidTile(x, y) then
    print("Tujuan di luar batas tile.")
    return
end

local path = bot:getPath(x, y)
for _, node in ipairs(path) do
    print(string.format("Node jalur: (%i, %i)", node.x, node.y))
end

local completed = bot:findPath(x, y) -- Blocking sampai operasi selesai.
if completed and bot:isInTile(x, y) then
    print("Bot mencapai tujuan.")
else
    print("Tujuan belum tercapai.")
end
```

v2.86 menjelaskan array Lua dimulai pada indeks 1. Gunakan `ipairs()` untuk
urutan node; contoh memakai `findPath()` untuk pergerakan dan memeriksa posisi
setelahnya. State dapat berubah selama operasi, sehingga query ulang bila terjadi warp/reconnect.

### Membaca seluruh bot

```lua
for index, bot in ipairs(getBots()) do
    print(string.format("Bot %i: %s", index, bot.name))
end
```

### Mendengarkan pesan dengan batas durasi

```lua
addEvent(Event.game_message, function(message)
    print(removeColor(message))
end)

listenEvents(30) -- Detik, bukan milidetik.
removeEvents()
```

## 13. Catatan ketidaksesuaian sumber

Bagian ini mencatat perubahan versi dan batas informasi sumber lokal.

| Bagian | Ketidaksesuaian dan penanganan |
| --- | --- |
| Versi campuran | Hanya `LUCIFER_LUA_V2_86.md` yang berjudul v2.86; empat sumber update lain lebih lama. |
| `connect()` | Return lama `boolean` diganti acuan v2.86: `nil`. Periksa `bot.status` kemudian. |
| Request item | `fastDrop`, `fastTrash`, pembelian item, dan `retrieve` mengembalikan boolean lokal; bukan konfirmasi server. |
| `findPath()` | v2.86 menjelaskan return boolean dan perilaku blocking. |
| `Inventory` | `itemcount` menghitung entri terisi; `slotcount` kapasitas total; `emptyslots` slot kosong. |
| Query world | `getTileParent(x, y)` menggantikan signature acuan lama yang menerima Tile. `hasAccess` tidak dijamin boolean. |
| Koordinat | `isValidTile` memeriksa tile; `isValidPosition` memeriksa pixel. Posisi Player/NetObject adalah pixel. |
| Tutorial | `auto_tutorial` adalah `AutoTutorial`, bukan boolean langsung. |
| AutoFarm | `setActive(state)` tercantum v2.86; tipe/rincian state tidak disediakan. Signature legacy dua argumen tidak disamakan. |
| Harvest/plant | v2.86 mencantumkan `storage`, `loop`, `add(world)`, `remove(world)`; grammar world/storage tidak dijelaskan ulang. |
| AutoParkour | `setReward` dikonfirmasi v2.86; typo `setWebhook` untuk reward pada v1.8 tidak lagi menjadi acuan nama. |
| Katalog item | v2.86 menamai tipe `ItemDescription` dan mencantumkan `strength`. Ketidakpastian lama mengenai keberadaan `strength` sudah terselesaikan pada dokumentasi baru. |
| Ubi bot | Argumen ketiga `addUbiBot` pada v2.86 adalah `otp_secret`, bukan username pendaftaran seperti contoh lama. |
| Bot guest | Bentuk `addBot(name)` dan `addUbiBot(email, password)` hanya ada di sumber lama. Bentuk tiga argumen `addBot(name, mac, rid)` masih disebut v2.86 tanpa penjelasan tipe akun. |
| Pembaruan akun | Ikuti urutan opsional `updateBot` v2.86; jangan menyalin bentuk tiga argumen lama sebagai `name, mac, rid`. |
| Webhook | Gunakan `message_id` dan `edit()` sesuai acuan v2.86; `edit(message_id)` hanya signature lama. |
| Interval rotation | Referensi lama bertentangan mengenai lokasi properti interval. Gunakan `getInterval`/`setInterval` dan enum `Action` sebagai API v2.86 yang jelas. |
| Rotation dan manager | v2.86 menyebut fitur secara ringkas; nama field lengkap, overload storage, `assign*`/`apply*` belum dikonfirmasi ulang. Tidak disimpulkan dihapus. |
| Enum login | `guest_disabled` ada di v2.32, `ubi_disabled` ada di v2.86; bukan alias yang terkonfirmasi. `CaptchaStatus` tidak dikonfirmasi ulang v2.86. |
| Struktur protokol | Rincian packet, vector, variant, RTVAR, dan `VariantType` disimpan sebagai referensi legacy; format tidak dirinci v2.86. |
| Typo sumber lama | Callback membaca variabel berbeda, contoh WorldManager memiliki `4584"`, AutoCrime disebut AutoFarm, dan komentar suhu `1` disebut low walau definisinya medium. Tidak dijadikan dasar contoh terbaru. |
| Bagian belum lengkap | Field `Credentials`, `Adventure`, `World.battle`, nilai enum `PlayerState`/`TileType`/`TileFlag`/`NpcType`, dan beberapa signature module tidak dirinci. |

### Anggota lain yang hanya dikonfirmasi referensi lama

Daftar ini merupakan informasi kompatibilitas, bukan daftar API yang dipastikan dihapus:

- Bot: `captcha_status`, `voucher_count`, `consumed_once`, `auto_take_pickaxe`,
  `move_interval`, `collect_interval`, `findWorldPath()`, dan `isInTile(Tile)`.
- Properti langsung `bot.console`, `bot.log`, serta raw collection
  `world.tiles`, `world.objects`, `world.players`, `world.npcs`, `world.adventures`,
  `inventory.items`; gunakan getter/query pada contoh baru.
- `ItemInfo`: `editable_type`, `item_category`, `hit_sound_type`, `item_kind`,
  `seed_color`, `seed_overlay_color`, `grow_time`, `drop_chance`, `texture_hash`,
  `texture_x`, `texture_y`, `null_Item`. Jangan menyimpulkan field baru sebagai alias.
- Player/Clothes: `avatarFlags`, `flag2019`, `unk1`, `unk2`.
- Automation: `AutoSpam.setText`, `AutoGeiger.afk`, `AutoFish.auto_rod`,
  `AutoFarm.speed`, `AutoMessage.uid_count`, `AutoMessage.messaging`, serta
  `AutoHarvest.setStorage` dan `AutoPlant.setStorage`.
- `Login.mac`/`rid`, batas skin 1–6, rentang indeks menu, pemetaan tipe automation,
  dan format separator world/storage lama belum dijelaskan ulang pada v2.86.

## 14. Troubleshooting dan kompatibilitas

### Lookup menghasilkan nil

Bot, pemain, tile, objek, NPC, item inventory, atau item katalog dapat tidak ada
pada snapshot saat ini. Periksa `nil` sebelum membaca properti. `getBot()` juga
dapat `nil` ketika script tidak mempunyai konteks bot.

### Aksi menghasilkan nil atau boolean tetapi efek belum terlihat

`nil` normal untuk metode aksi tanpa laporan hasil. Boolean pada request lokal
bukan konfirmasi penerimaan server. Ambil state baru atau gunakan event untuk
memeriksa efeknya, misalnya posisi sesudah warp atau jumlah inventory sesudah drop.

### State world tiba-tiba berubah

Warp, redirect, reconnect, dan map update dapat mengganti state. Ambil ulang
`getWorld()` dan snapshot sesudah transisi, bukan membaca objek lama terus-menerus.

### Event tidak berjalan atau script lambat berhenti

Daftarkan callback sebelum `listenEvents(timeout_seconds)`. Listener bersifat
blocking dan terbatas durasi; panggil lagi untuk jendela dengar berikutnya.
Callback panjang serta operasi blocking dapat menunda cooperative shutdown.

### Menjalankan script lintas versi

Periksa anggota opsional sebelum digunakan. Ini hanya memeriksa keberadaan
anggota, bukan menjamin seluruh signature dan perilaku sama antarversi.

```lua
local bot = getBot()
if bot == nil then return end
if bot.getSignal ~= nil then
    local signal = bot:getSignal()
    print(signal.x .. ", " .. signal.y)
end
```

Untuk perilaku yang belum dijelaskan, cocokkan versi aplikasi dengan sumber lokal
yang relevan sebelum menyimpulkan nama field, satuan, overload, atau nilai parameter.
