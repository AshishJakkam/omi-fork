# What is private, and what is not

Written from the code and configuration in this repo, not from memory. If a claim here is not
backed by a file, treat it as unverified.

## The trust chain

| Party | Sees | Can avoid? |
|---|---|---|
| **Omi (BasedHardware)** | **Nothing.** Self-hosting removes them from the path entirely. | already avoided |
| **Fly.io** | Data at rest on the volume, and traffic through their network. | yes, any host works |
| **Google** | Firebase metadata, Firestore contents, and anything sent to Gemini. | partly |
| **You** | Everything. Your server can read every transcript. | inherent |

Self-hosting is a real privacy improvement because it removes a third party that had no reason to
exist. It is not anonymity, and it is not end-to-end encryption.

## Audio is the decision that matters

Two modes, materially different:

| Mode | Audio path | Privacy |
|---|---|---|
| **On-device** (Apple SpeechAnalyzer / Whisper) | never leaves the phone; only text is uploaded | strongest |
| **Gemini Live** (bring-your-own key) | streams **directly to Google** under Google's terms | weaker |

`env.selfhost.template` assumes the first: *"iOS transcribes on-device (Apple SpeechAnalyzer), so
no cloud STT is used for phone capture."*

Choosing Gemini Live for better Indic accuracy trades privacy for quality. That trade is the
operator's to make, but it should be made knowingly rather than by default.

## What the configuration already protects

- `OMI_ENV_STAGE=offline` / `PROVIDER_MODE=offline` — instance filesystem instead of GCS buckets, so
  no object storage is created and no `BUCKET_*` credentials exist.
- `ENCRYPTION_SECRET` — encrypts stored transcripts and page cursors; startup refuses to serve
  without it.
- Firestore production rules — no public read or write. The phone never talks to Firestore
  directly; only the backend does, with the service account.
- Audio is never uploaded to Omi.

## In-app switches worth knowing

- **Keep everything on this phone** (`keepEverythingOnDevice`) — the subtitle in the app reads
  *"Transcripts only, no summaries"*. Enabling it stops summaries, because summarising requires
  sending text to a model. That is the honest trade: maximum local privacy, no AI features.
- **Send raw audio to Omi** (`sendRawAudioToOmi`) — on a self-hosted backend this target is your own
  server, not Omi's.

## The single most sensitive file

`backend/secrets/firebase-service-account.json` is a private key granting **admin rights** to the
whole database. It bypasses Firestore rules, which is exactly why the phone does not hold one.

- Gitignored — verified with `git check-ignore`.
- Never paste its contents anywhere; if it leaks, revoke the key in the console and generate a new
  one.
- The Gmail account that owns it (`aiwearablepilot@gmail.com`) is now the root of trust. Enable 2FA
  and set recovery before real use.

## What this document does not claim

- Not anonymous: Google sees Firebase traffic; Fly sees the host.
- Not end-to-end encrypted: your server holds the keys and can read plaintext.
- Not audited: no third party has reviewed this configuration.
