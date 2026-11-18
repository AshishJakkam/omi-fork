# Getting a fully unlocked backend running

Ordered steps. Everything marked **you** is a console action under your Google account; everything
else is already scripted and committed.

Run the checker at any point to see exactly what is still missing:

```powershell
powershell -ExecutionPolicy Bypass -File backend\selfhost\preflight.ps1
```

## 1. The Google account — **you**

A dedicated Gmail for this project. `aiwearablepilot@gmail.com`, not `aiwearable_pilot@` —
**Gmail usernames do not allow underscores** (letters, numbers and periods only), and dots are
ignored, so `ai.wearable.pilot@` is the same inbox.

Choose **free Gmail**, not Workspace: a custom domain would force you to commit to a brand name,
and this address is never shown to your users — the OAuth consent screen displays your project
name instead.

Before anything else: turn on **2FA** and set a **recovery email and phone**. This account will own
your Firebase project and your deployed backend.

## 2. Firebase project — **you**

1. <https://console.firebase.google.com> → **Add project**. Name it neutrally (`omi-selfhost`).
   The project **ID is immutable** but never user-visible, so it does not lock the brand.
2. **Firestore Database** → create, production mode.
3. **Authentication** → Get started → enable **Google**.

## 3. OAuth client — **you**

1. <https://console.cloud.google.com/apis/credentials> (same project) → **Create credentials** →
   **OAuth client ID** → **Web application**.
2. Authorised redirect URI — exactly this, no trailing slash:
   ```
   https://omi-open.fly.dev/v1/auth/callback/google
   ```
   If you change the Fly app name, the host changes with it; `fly.toml` holds `omi-open`.
3. Copy the **client ID** and **client secret**.
4. **OAuth consent screen** → External → Testing, and add your own Gmail as a **test user**.
   Testing mode is fine for you and a few testers; opening it publicly needs Google verification.

## 4. Service account — **you**

Firebase console → **Project settings** → **Service accounts** → **Generate new private key**.
Save the JSON as:

```
backend\secrets\firebase-service-account.json
```

That path is gitignored, along with `backend/.env`.

## 5. App-side Firebase config — **you**, but this one is easy to forget

A `self_host` build accepts whatever Firebase project the app was initialised with, so a stale
config is **not** rejected at startup — it authenticates against Omi's project while calling your
backend, and fails much later with an auth error that looks unrelated.

Replace all three, generated from **your** project (`flutterfire configure`, or download from the
Firebase console):

```
app\setup\release-firebase\firebase_options_prod.dart
app\setup\release-firebase\google-services.prod.json
app\setup\release-firebase\GoogleService-Info.prod.plist
```

Preflight fails if any of them still names `based-hardware`.

## 6. Fill in `backend/.env` — **you**, four values

Already populated: `OMI_SELFHOST_UNLIMITED=true`, `OMI_ENV_STAGE=offline`, `PROVIDER_MODE=offline`,
`ENCRYPTION_SECRET` (generated), `GEMINI_API_KEY`.

Still needed:

| Key | Value |
|---|---|
| `BASE_API_URL` | `https://omi-open.fly.dev` — **no trailing slash** |
| `FIREBASE_AUTH_PROJECT_ID` | your project ID |
| `FIREBASE_AUTH_DOMAIN` | `<project>.firebaseapp.com` |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | from step 3 |

## 7. Deploy — scripted

```powershell
fly auth login          # if not already
powershell -ExecutionPolicy Bypass -File backend\selfhost\deploy.ps1 -AppName omi-open
```

It creates the app and volumes, imports secrets without echoing them, and deploys. Use
`-SkipDeploy` to stop after secrets so you can inspect the build first.

## 8. Build the app against it — scripted

```powershell
gh workflow run ios-unsigned.yml -R <you>/omi-fork --ref fresh-v2 `
  -f app_profile=self_host `
  -f api_base_url=https://omi-open.fly.dev/ `
  -f force_on_device=true `
  -f include_watch=false
```

`force_on_device=true` compiles the on-device override, which a `self_host` build expects.

## 9. Confirm the unlock took

What "fully unlocked" means concretely, from `backend/utils/subscription.py`:

- `is_paid_plan()` returns true for every plan
- `get_plan_limits()` returns `None` for `transcription_seconds` and `chat_questions_per_month`
- nothing is ever exhausted, so `is_locked` is never written and history stays readable

In the app, after signing in: Plan & Usage should stop showing 300 minutes and 30 questions, and no
Upgrade prompts should appear.

## What this costs

One LLM key (the Gemini key is already wired) plus Fly hosting. On-device transcription is free.
