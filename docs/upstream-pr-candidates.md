# Fork changes, and what belongs upstream

Two things in one place: everything this fork changed, and — separately — which of those are real
improvements to Omi rather than to *this* deployment, with enough detail to open a PR against
[BasedHardware/omi](https://github.com/BasedHardware/omi).

A change belongs upstream when it fixes behaviour an ordinary Omi user or contributor can hit. It
does **not** belong upstream when it exists because this fork has a different bundle ID, a
different backend, or no Apple Developer account.

---

## 1. What this fork changed

### Track A — making on-device transcription actually work

| Commit | Change |
|---|---|
| `2ee4d9d` | `OMI_ON_DEVICE_OVERFLOW_FORCE` opens the on-device path in release builds; the PostHog gate was fail-closed with a `kDebugMode`-only override, so a shipped build could never fall back to on-device. Adds `on_device_overflow_gate_force_test.dart`. |
| `e1470d5` | iOS uses local Whisper when a model is present, with per-chunk Apple fallback. Also fixes `multi` being passed to `apple.transcribe()`, which only accepts a concrete locale. |
| `6b4afeb` | The model chosen in settings is the model that runs (`chooseModelPath`), instead of a fixed tiny→large probe. Settings now detects any installed model, and iOS gets the model section it never had. Nine tests. |

### Track B — pointing the app at a backend its operator runs

| Commit | Change |
|---|---|
| `927e1b9` | Fork targets a self-run backend instead of Omi's cloud. |
| `5daedbb` | `backend/selfhost/`: Dockerfile on a public base image (upstream uses a private GCR image), `fly.toml`, `env.selfhost.template`, README. |
| `b731f23` | `AppEnvironmentProfile.selfHost` + relaxed startup routing validators. Before this, any non-Omi URL was *refused* and the app rendered `StartupFailureApp`. |
| `17ed0b9` | `OMI_SELFHOST_UNLIMITED` in `utils/subscription.py`: an owned deployment's plans are unlimited. Ships as a patch that applies to pristine upstream. |
| `c3a69e6` | `deploy.ps1` (one command: app + volumes + secrets), plus gitignore protection for `backend/secrets/`. |
| `529292c` | `preflight.ps1`: read-only prerequisite check that prints the exact OAuth redirect URI to register. |
| `bd2075d` | `PAYMENTS.md` — what taking money on your own deployment requires. |

### Track C — building and installing without a paid Apple account

| Commit | Change |
|---|---|
| `0c92ead` | Target Omi's cloud so the phone works untethered. |
| `e6d019c` | `RunnerRelease-fork.entitlements` with no entitlements, so a free Apple ID can sign. |
| `98caa9e` | OAuth callback scheme had drifted apart across AndroidManifest, xcconfig and Dart; unified, plus `fork_identity_consistency_test.dart`. |
| `55da422` | `ios-unsigned.yml`: build an unsigned IPA on a GitHub macOS runner. |
| `f0e0dfa` | Retry `pod install`, which died on a Twilio CDN 504. |
| `dfaf84e`, `be7332c`, `9c870b9`, `c2975db` | Restore the gitignored `firebase_options` file before building; install Firebase config via the upstream script instead of by hand; read the plist the install step really writes; match the unquoted value the generator really writes. |
| `8e3ba3b` | Seed the Runner plist Xcode requires as a build input. |
| `62518df` | Parameterize the workflow (`api_base_url`, `app_profile`, `force_on_device`, `include_watch`) so one workflow builds both configurations. |
| `c7b136c` | The watch app is opted into, not hard-stripped. |

### Track D — identity

| Commit | Change |
|---|---|
| `ad663a7` | Rebrand across 25 files: bundle id, URL scheme, App Group, display name, Android package. Adds an app-group consistency test, because a missed Swift consumer of the App Group fails silently. |
| `3577b1f`, `f8bad24` | `iphone/restore-to-openmind.ps1`: move the Whisper model and rescued recordings into a reinstalled app's container, clearing other models first via `fsync rm`. |

---

## 2. PR candidates, best first

Ranked by (a) how obviously correct the fix is, (b) how little it depends on this fork, (c) how
likely a maintainer accepts it.

### PR 1 — Honour the selected speech model (bug fix) — ✅ **SENT as [#25121](https://github.com/BasedHardware/omi/pull/25121)**

**Status.** Opened against `BasedHardware/omi` `main` at `245f8174b1`. Two commits, three files,
+135/−25. Verified there: `flutter analyze` clean, 8/8 tests pass, `dart format` unchanged.

Note: a PR to upstream is only possible from a real GitHub **fork**. `AshishJakkam/omi-fork` is a
standalone repo (not a fork), so nothing could be sent from it. `AshishJakkam/omi` was forked from
upstream for this; the working clone lives at `C:\omipr` (sparse: `app` + `backend/utils`).

**Problem.** `FreemiumTranscriptionService._findDownloadedModelPath()` walks a hardcoded
`['tiny','base','small','medium','large-v1','large-v2']` list and returns the first file present.
The settings page lets you choose a model and download it, but if an older, smaller model is still
in `models/`, the choice is ignored — silently. A user who downloads `base` for Telugu gets `tiny`
and no explanation.

**Fix.** A pure `chooseModelPath(binPaths, {preferredModel, preferredPath})` that consults the saved
`CustomSttConfig` (path, then name) before falling back to the size heuristic.

**Why a maintainer takes it:** it is a one-function bug fix at a call site that already exists, it
has a failing case anyone can reproduce (two models on disk), and it makes an existing UI control
work. Files: `app/lib/services/freemium_transcription_service.dart`,
`app/test/unit/on_device_model_selection_test.dart`.

### PR 2 — Stop passing `multi` to Apple's transcriber — ❌ **WITHDRAWN, upstream already handles it**

I believed `AppleBatchEngine.transcribe` receives `multi`, which is not a locale. Checking current
`main` before sending: `AppleBatchEngine` does pass the string straight through, **but** nothing lets
`multi` reach it — `SttLanguage.derived()` maps `multi` → `en` on iOS
(`app/lib/pages/settings/transcription/stt_language.dart:40`), `SttLanguage.supported()` filters
`multi` out of the picker on iOS, and `OnDeviceAppleProvider.transcribe` maps it again at
`on_device_apple_provider.dart:114`. The fork's version of this fix was justified against an older
base. Sending it would have been a speculative patch with no reproducible failure, so it was
dropped rather than filed.


### PR 3 — Use Whisper on iOS when a model is installed (feature)

**Problem.** The iOS settings branch returns early with "Using Native iOS Speech Recognition", and
the runner only ever used Apple's engine. Whisper's iOS pod already ships in
`whisper_flutter_new` and the model-directory lookup was never platform-gated — the capability was
there, unreachable.

**Fix.** Try Whisper first when `models/ggml-*.bin` exists; fall back to Apple per chunk on any
failure, so a bad model can never wedge the recording queue.

**Why a maintainer takes it:** Apple's on-device engine is weak for languages including Telugu and
Hindi; the fallback makes the risk near zero. Pair it with the UI change below.

### PR 4 — Show the model section on iOS (feature)

**Problem.** With PR 3 in, a model can be installed and in use on iOS with no way to see which one,
change it, remove it, or download one.

**Fix.** Extract `_buildWhisperModelSection()` and render it in the iOS branch under an "optional"
heading, with copy that says Apple remains the default. Adds two l10n keys (`iosWhisperTitle`,
`iosWhisperHelp`) and regenerates locales (English fallback for the rest).
File: `app/lib/pages/settings/transcription_settings_page.dart`.

### PR 5 — Detect any installed model in settings (bug fix) — ✅ **included in [#25121](https://github.com/BasedHardware/omi/pull/25121)**

**Problem.** `_checkLocalModel()` only looks for `models/ggml-<currentModel>.bin`. A model present
under any other name is invisible: the row says "not downloaded" while transcription uses that very
file.

**Fix.** List the directory and select through the same `chooseModelPath`, then record the model
name it found so the picker agrees with reality.

**Why it went out with PR 1:** without it, PR 1 makes the app run the right model while this page
still reports the wrong one. They are the same class of bug and reading them together is easier.


### PR 6 — Retry `pod install` on a CDN failure (CI)

**Problem.** `pod install` failed repeatedly on a Twilio CDN 504 — a transient network error that
aborted an otherwise fine build.

**Fix.** Bounded retry around the step.

**Why a maintainer takes it:** no behaviour change, removes a flaky failure.
File: `.github/workflows/ios-unsigned.yml` (or `codemagic.yaml` upstream).

### PR 7 — `install_release_firebase_config.sh` assumes a plist that may not exist

**Problem.** The script writes into a Runner plist Xcode expects; on a clean checkout that file is
absent, so the step fails before the build starts.

**Fix.** Seed the plist as a build input when missing.

**Why a maintainer takes it:** it is a clean-checkout failure in an upstream script, not a fork
quirk. File: `app/scripts/install_release_firebase_config.sh`.

### PR 8 — One test for OAuth scheme / App Group agreement (test)

**Problem.** The callback scheme and the App Group are each declared in several places (Dart config,
AndroidManifest, xcconfig, entitlements, Swift `UserDefaults(suiteName:)`). They had drifted apart
in two of three places, and a mismatched App Group fails *silently* — no crash, no warning, just
missing data.

**Fix.** A test asserting the Dart scheme equals the manifest/xcconfig declarations, and that every
Swift App Group consumer matches the entitlement.

**Why a maintainer takes it:** pure test addition guarding a real class of silent bug. This one is
valuable outright, independent of everything else here.

### PR 9 — Issue: on-device transcription failures leave recordings stuck and invisible

**Evidence.** A device's `wals.json` held 1,056 entries; **1,033 were `status=miss`,
`on_device_only=true`, with no transcript**. Only 23 were cloud-transcribed. The failures were
invisible in the UI — the recording list showed nothing wrong — and of those 1,033 entries only 61
still had audio on disk; the rest had been cleaned up after upload, so the audio was gone with no
transcript ever produced.

**Ask.** Surface the failure state (a count/banner with a retry), and do not clean up audio for a
record that produced no transcript. This is worth filing as an issue before attempting a PR.

### PR 10 — `selfHost` environment profile (feature, needs discussion)

**Problem.** Startup validation refuses any API base that is not Omi's, rendering
`StartupFailureApp`. That blocks the self-hosting the MIT licence implies.

**Fix.** An `AppEnvironmentProfile.selfHost` with validated-but-not-hardcoded routing, plus
`validateStartupRouting` relaxation. Open an issue first — this is a product decision for Omi, and
it is the foundation of `backend/selfhost/`.

---

## 3. Do not send these upstream

- **Track D rebrand.** Bundle ID, scheme, App Group and display name are this fork's identity.
- **`e6d019c` free-tier entitlements.** Exists because there is no Apple Developer account.
- **`17ed0b9` `OMI_SELFHOST_UNLIMITED`.** Deliberately removes the paywall; it is the point of the
  fork. Keep it as a patch (`backend/selfhost/patches/`), not a PR.
- **`iphone/restore-*.ps1`.** Windows/PowerShell tooling for one specific device. The useful part
  is one fact: `ios fsync` supports `rm|tree|mkdir`, which `ios file` does not.
