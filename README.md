# Lucifer Scripts (v2.86)

Koleksi skrip otomatisasi untuk Lucifer Growtopia v2.86.

## Skrip Rotasi (`rotation_final.lua`)
Alur kerja rotasi berbasis State Machine:
`HARVEST` → `BREAK_HOME` → `PLANT` → `STORE` → `NEXT_WORLD`

### Fitur & Proteksi
- Anti-desync v2.86 (`bot.leave_world_before_warp`, validasi ganda `isInWorld`).
- Auto-reconnect (`waitOnline`).
- White Door (ID 6) recovery via `bot:warp(world, door)`.
- Punch stuck safety cap.
