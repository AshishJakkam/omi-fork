# Porting the fork onto a fresh Omi clone

Measured against upstream `5097caa6f7` (the commit that was `origin/main` when this was written).
The fork was re-initialised from a snapshot dated 2026-11-07, so it shares no git history with
upstream — `git diff` and `merge-base` are useless here, and a `cherry-pick` is the only
transfer mechanism.

## The headline

Two of our commits fix bugs that still exist in upstream today:

1. **Captured audio is withheld when the plan is exhausted.** Upstream gates the socket on
   `!shouldKeepAudioLocal` with no escape. A bring-your-own API key therefore produces an empty
   live transcript while the recording looks healthy. Verified present at
   `app/lib/services/capture/capture_controller.dart:625,2394,3141,4803`.
2. **Gemini ignores the primary language.** Upstream passes `config.effectiveLanguage` straight
   through at `app/lib/services/sockets/transcription_service.dart:598` instead of resolving it,
   so a saved `en` outranks Telugu or Hindi.

Both are fixed by `01-transcription-uplink-language.patch` in this folder — 36 lines, three files.
It is verified to apply cleanly to pristine upstream, to analyse with no new issues, and to leave
58 of upstream's own STT tests passing.

```powershell
git clone https://github.com/BasedHardware/omi.git
cd omi
git apply docs/fork-patches/01-transcription-uplink-language.patch
```

## Cherry-pick status

Tested by replaying each commit onto a pristine upstream worktree.

### Applies cleanly

| Commit | What it does |
|---|---|
| `5daedbb5` | Self-hosted backend deployment (Dockerfile, fly.toml, env template) |
| `17ed0b9d` | `OMI_SELFHOST_UNLIMITED` — unlimited allowances, every plan treated as paid |
| `b731f23f` | Let a build target a backend its operator runs |
| `529292c6` | Pre-flight self-host prerequisites before spending a deploy |
| `bd2075d2` | `PAYMENTS.md` — taking payments on your own deployment |
| `e71f1c0b` | Resolve Gemini's language like every other provider |
| `423e189c` | Name the field a 422 rejects |
| `c7ba3035` | Say what shape a 422 body has |

### Conflicts, and why

| Commit | Conflicts on | Nature |
|---|---|---|
| `e5a1db77` | `capture_controller.dart` | Upstream refactored the gate; use the patch file instead of cherry-picking |
| `15841757`, `25eb03d1`, `d5c1e6de` | `transcription_settings_page.dart`, `stt_model_catalog.dart` | Upstream's settings page moved on; re-apply by hand or re-implement from the description |
| `83292328`, `73f51342` | `on_device_runner.dart` | Same — upstream restructured the runner |
| `927e1b9e`, `0c92ead1`, `62518dfc`, `c3a69e6b` | `codemagic-fork.yaml`, `ios-unsigned.yml`, `.gitignore` | These build on earlier commits of **ours**; apply in order and they resolve |

## What is worth re-implementing, in order

1. **Self-host + unlimited** (group A) — this is the product. Backend files transfer as-is.
2. **The uplink + language fix** — already packaged as a patch here.
3. **On-device Whisper work** (group D, ~20 commits) — the hardest-won part, and it does not
   cherry-pick cleanly. It depends on our `whisper_flutter_new` fork
   (`AshishJakkam/whisper_flutter_new`, branch `persistent-context`), which lives outside this
   repository and must be re-pointed in `pubspec.yaml` before any of it compiles.
4. **Live model catalogue + cost visibility** (`stt_model_catalog.dart`, `stt_usage_tracker.dart`)
   — both are new files, so they travel whole; only their call sites need re-wiring.
5. **Backlog/provider parity** (group E) — re-implement against the new runner structure.
6. **Diagnostics and tooling** (groups G, H) — cheap to redo, low risk.

## Do not re-implement

- `35dd176b` and `78423308` — audio conditioning that was reverted in `c4d5646a`. The evidence
  behind it came from recordings made while nobody was speaking.
- The seven per-config `.entitlements` files. One free-tier entitlements file was enough; the rest
  was fighting Xcode, and upstream may build cleanly now.
- `codemagic-fork.yaml` if the build stays on GitHub Actions.

## Order of operations, given the naming decision

The trademark only blocks the *public* identity, not the engineering:

1. Fork fresh upstream; apply the patch. Nothing here depends on the name.
2. Self-host the backend. The Firebase **project id is immutable**, but it is never shown to
   users — name it neutrally (`<something>-selfhost`) so the brand can be decided later.
3. Settle the brand.
4. Only then set the bundle id, display name and store listing.
