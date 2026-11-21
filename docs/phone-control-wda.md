# Controlling the phone over USB (go-ios + WebDriverAgent) on Windows
# Verified working on 2026-11-21: a prior session wrongly declared this impossible
# without a paid Apple account or a Mac. It is not. This flow drove the UI for days
# in the main work session.

## The exact working sequence
```bash
IOS="C:\\Users\\ashis\\Tools\\go-ios\\ios.exe"
UDID=00008140-001475300E11801C
RUNNER=com.facebook.WebDriverAgentRunner.xctrunner.WB98TW9DCS   # MUST keep the .WB98TW9DCS suffix

# 1. Userspace tunnel (exposes device RSD on 127.0.0.1:60105)
"$IOS" tunnel start --userspace --udid=$UDID

# 2. Launch WDA, passing the SUFFIXED bundle id for BOTH bundle-id flags
"$IOS" runwda --udid=$UDID --tunnel-info-port=60105 \
  --bundleid="$RUNNER" --testrunnerbundleid="$RUNNER" \
  --xctestconfig=WebDriverAgentRunner.xctest

# 3. CRITICAL: forward the HTTP port AFTER WDA starts
"$IOS" forward 8100 8100 --udid=$UDID

# 4. Verify, then drive the UI
curl http://127.0.0.1:8100/status        # -> 200 = good
# POST /session {bundleId}, then /source, /wda/tap, /screenshot
```

## The two mistakes that make it LOOK impossible
1. Passing the bare bundle id (without -WB98TW9DCS) so testmanagerd misses the installed runner.
2. Forgetting to `forward 8100 8100` -- /status is then unreachable and it looks like "WDA failed."

## The real blocker is the lock screen, not signing
- If the runner hangs at `_XCT_didFormPlanWithData:` for >30s, the device is LOCKED to a passcode
  (MDM auto-lock sets it every <=5 minutes). Unlock it and set Settings > Display > Auto-Lock to
  Never for the session.
- App-launch returning code 1 / RequestDenied / "device was not, or could not be, unlocked" is the
  lock screen. `ios screenshot` works while locked, launching an app does not -- that asymmetry is
  the tell.

## Genuine iOS 26 limits (irrelevant to UI driving)
- `ios file ls` / `file pull` on a private app data container and DDI cold-boot restrictions are
  real -- but they do not affect WDA /session + /wda/tap + /source + /screenshot paths.
