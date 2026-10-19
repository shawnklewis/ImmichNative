# ImmichNative

Runs Immich natively on Windows (no Docker/WSL). Prototype ports so it can sit beside a live Docker Immich:
Postgres 14 + pgvector on 5433, Redis on 6380, Immich on 2284, ML on 3004 (not yet set up).

- scripts/build-pgvector.cmd - compile pgvector against the portable Postgres (needs MSVC Build Tools)
- scripts/build-immich.ps1   - build Immich v3.3.3 server + web from vendor/immich
- scripts/start-server.ps1   - start the server with the prototype environment
- patches/                   - Windows fixes applied to vendor/immich (git apply from vendor/immich)

vendor/, tools/ (portable Postgres, Redis) and run/ (logs, secrets) are git-ignored.
Known: Redis 5.0.14 (Windows port) only triggers Immich's "recommended 6.2" warning.

## Data layout (everything to back up is on D:)
- D:\ImmichNative\pgdata   live Postgres cluster (don't copy while running; use the dumps)
- D:\ImmichNative\media    photos/videos (back this up)
- D:\ImmichNative\redis    Redis snapshots (dump.rdb; queues only, safe to lose)
- D:\ImmichNative\backups  pg_dump archives from scripts/backup-db.ps1 (keeps 14, verified on write)
- D:\ImmichNative\build    geodata, plugins, web build (rebuildable)
C: holds only programs and source (tools/, vendor/) and the secrets file run/pg.env, which is deliberately not backed up with the data.
Restore: create a database, then pg_restore --no-owner -d <db> <file>.dump.

## Known gaps
- HEIC/HEIF (HEVC) images get no thumbnail: sharp's bundled libvips on Windows has no HEVC decoder (Docker's image builds its own with libde265).
  Only 2 of 5,441 library photos are HEIC; parked on 2026-10-19 to revisit around 2026-10-26.
  Plan when revisited: patch Immich thumbnail generation to fall back to ffmpeg (verified: ffmpeg decodes both files to full 4032x3024 JPEG).
  A native HEVC build is not worth it: sharp has no global-libvips option on Windows, so it would mean rebuilding the sharp-libvips package.
