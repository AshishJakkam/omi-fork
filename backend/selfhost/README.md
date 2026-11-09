# Self-hosting the Omi backend

Running your own backend is what removes the free-plan limits. Those limits are not in the app â€”
they are values in a plan catalog this deployment owns:

| Limit | Where it lives | Under self-host |
|---|---|---|
| 300 transcription minutes/month | `backend/config/plan_catalog_generated.py` (`basic` â†’ `transcription` â†’ `18000` seconds) | yours to set |
| 30 chat questions/month | same file (`basic` â†’ `chat` â†’ `30`) | yours to set |
| Conversations hidden behind Upgrade | server-written `is_locked` field, cleared by `unlock_conversations` | never written; `unlock_all_conversations(uid)` available |

Speech is the expensive part, so the design leans on the phone: **iOS transcribes on-device**
(`AppleBatchEngine`), and uploads text only to `POST /v1/conversations/from-segments`, which is
Firebase-authed plus rate limited â€” it does **not** meter transcription minutes.

## Why sign-in still works from a fork

A sideloaded build has its own bundle id, so Google will not issue it an OAuth client. It does not
need one: the app opens `BASE_API_URL/v1/auth/authorize`, Google returns to
`BASE_API_URL/v1/auth/callback/google`, the backend exchanges the code server-side with your **web**
OAuth client and mints a Firebase custom token in your project. The app only calls
`signInWithCustomToken`. Confirmed working locally â€” `POST /v1/auth/local-dev/custom-token`
returns a valid 384-character JWT.

## What you must create

1. **A Firebase project.** Firestore + Auth. Keep it on the Spark (free) plan to start; Firestore's
   1 GB free tier is far beyond text transcripts.
2. **A Google OAuth *web* client** in that project, with the callback URL
   `https://<your-app>.fly.dev/v1/auth/callback/google`.
3. **A service account JSON** for that project (used to mint custom tokens and touch Firestore).
4. **One LLM key.** This is the only unavoidable running cost. On-device transcription is free.

## Build and run

```bash
# from the repository root â€” the context needs backend/ and .github/scripts/
docker build -f backend/selfhost/Dockerfile -t omi-selfhost .

cp backend/selfhost/env.selfhost.template backend/.env
# fill in the CHANGE-ME values, then:
docker run --rm -p 8080:8080 \
  -v "$PWD/backend/secrets:/app/secrets:ro" \
  -v "$PWD/data:/app/syncing" \
  --env-file backend/.env omi-selfhost
```

Fly.io:

```bash
fly launch --no-deploy --name <your-app> --region bom
fly volumes create omi_data    --size 3 --region bom
fly volumes create omi_secrets --size 1 --region bom
fly secrets import < backend/.env
fly deploy --dockerfile backend/selfhost/Dockerfile
```

## Point the app at it

The build is compile-time: `envied` bakes `.env` into `lib/env/*.g.dart` during `build_runner`, so
these must be set **before** that step.

```
API_BASE_URL=https://<your-app>.fly.dev/
USE_WEB_AUTH=true
USE_AUTH_CUSTOM_TOKEN=true
```

The app's `API_BASE_URL` **does** keep its trailing slash (the client concatenates `v1/...`), while the
backend's `BASE_API_URL` must **not** have one. They are different variables with different rules â€”
mixing them up produces a doubled slash in the Google callback URL.

Then rebuild with `--dart-define=OMI_ON_DEVICE_OVERFLOW_FORCE=true` so on-device transcription runs
without waiting for the PostHog flag, and sideload the new `.ipa`.

## Migrating existing data

Your current recordings live in Omi's Firebase project. A new project starts empty. The archived
34.49 GB iOS backup is the copy you can extract and import later; there is no way to re-point the
existing rows at a different project.
