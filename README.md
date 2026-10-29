# Lucifer Rotation (v2.86)

Koleksi skrip otomatisasi rotasi farm untuk Nuron's Lucifer Growtopia v2.86.

## Struktur Berkas

- **`loader.lua`**: Skrip ringan untuk dijalankan di Lucifer bot. Hanya berisi tabel konfigurasi (`CONFIG`) dan mengambil `engine.lua` secara realtime dari GitHub Raw.
- **`engine.lua`**: Logika utama rotasi (State Machine) yang di-host di GitHub. Pembaruan logika atau bug fix dilakukan di sini tanpa perlu mengubah skrip di setiap bot.
- **`rotation_final.lua`**: Skrip standalone lengkap (offline mode).
- **`docs_v2.86.md`**: Dokumentasi referensi lengkap API Lucifer v2.86 berbahasa Indonesia.

## Alur Kerja Rotasi

```text
Mulai → Masuk World → Scan Tree → Harvest & Collect (batch) → Break di Home → Balik & Plant → Cek Gems & Auto Buy Pack → Simpan Seed & Drop Item Pack di Storage → Next World
```

## Fitur Utama Baru
- **Live Webhook Monitor (`webhook_edit`)**: Mengirim dan mengedit satu pesan Discord secara realtime (`webhook:edit()`) menampilkan nama bot, status online/offline, world aktif, gems, slot inventory, ping, dan jumlah item pack di tas.
- **Auto Buy Pack & Storage Drop**: Otomatis membeli pack dari Store ketika gems mencukupi (`PricePack`), lalu menjatuhkan item pack (`ItemIDOfPack`) pada koordinat placement (`DropPlacement`) di world storage.

## Cara Penggunaan

1. Buka `loader.lua` di bot Lucifer.
2. Sesuaikan konfigurasi di tabel `CONFIG`:
   - `FARMS`: Daftar world target panen dan tanam.
   - `HOME`: World pemecahan blok.
   - `STORAGE`: World penyimpanan seed dan item pack.
   - `BLOCK_ID` & `SEED_ID`: ID blok dan seed tanaman.
   - `WEBHOOK`: URL webhook Discord dan Message ID (opsional untuk live edit).
   - `AUTO_BUY_PACK`: Pengaturan pack name, harga, delay, dan drop placement.
3. Jalankan `loader.lua`. Bot akan mengunduh engine terbaru dan langsung mengeksekusi rotasi.

## Proteksi & Safety v2.86
- **Anti-Desync**: Mengaktifkan `bot.leave_world_before_warp`, validasi ganda `bot:isInWorld()`, dan post-warp settling delay.
- **White Door Recovery (ID 6)**: Jika bot terkena event atau mati/respawn ke White Door, bot otomatis re-warp ke door target atau berjalan kembali ke posisi kerja.
- **Auto-Reconnect (`waitOnline`)**: Menahan eksekusi saat bot disconnected dan melanjutkan otomatis setelah online kembali.
- **Punch Stuck Guard**: Membatasi percobaan pemukulan per blok agar bot tidak stuck saat menghadapi blok kebal atau packet lag.
