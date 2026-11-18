# What this actually costs

Numbers are as of November 2026 and are **estimates**, not quotes. Verify before relying on them.

## The headline

**Hosting is not the expensive part.** For a single user, the model API dominates — and it is the
one line item that scales with how much you talk.

| Line item | Personal use (1 user) | Notes |
|---|---|---|
| Firebase (Firestore + Auth) | **$0** | free tier is far beyond one person |
| Hosting (Cloud Run) | **$0** | free tier; see cold-start caveat |
| Gemini transcription | **$3–30/mo** | depends entirely on hours transcribed |
| Gemini summaries/memories/chat | **$1–5/mo** | flash-lite, tiny token counts |
| Domain (optional) | $0–12/yr | not required; `*.fly.dev` works |

## Firebase — realistically $0

Spark (free) plan limits:

| Resource | Free per day/month | What one user needs |
|---|---|---|
| Firestore storage | 1 GiB total | ~10–50 KB per conversation → **20,000+ conversations** |
| Document reads | 50,000/day | tens per conversation |
| Document writes | 20,000/day | ~5–20 per conversation |
| Network egress | 10 GiB/month | negligible for text |
| Auth (Google sign-in) | free | one user |
| Cloud Storage | **not used** — `PROVIDER_MODE=offline` | — |
| Analytics, Crashlytics | free | — |

A one-hour conversation is roughly 10–50 KB of transcript text. You would need **years** of daily
use to approach 1 GiB. Blaze (pay-as-you-go) only becomes relevant past those limits, and at that
point you would be paying cents.

**Do not enable Blaze unless you have to.** Spark is enough and cannot generate a surprise bill.

## Hosting — three ways to $0, one to "just works"

| Option | Monthly | Always on? | Trade-off |
|---|---|---|---|
| **Cloud Run** (what Omi uses) | **$0** in free tier | no — scales to zero | 15–30 s cold start with this image |
| **Oracle Always Free** | **$0** forever | yes | ARM build; signup friction; you patch the OS |
| **Fly.io** (configured now) | ~$3–7 | yes | costs money |
| Hetzner CX22 | ~€4 | yes | you manage the OS |

### Cloud Run free tier, per month

- 180,000 vCPU-seconds → 50 hours at 1 vCPU
- 360,000 GiB-seconds → 100 hours at 1 GiB
- 2 million requests
- 1 GiB egress **from North America** — egress from other regions may be billed, so deploying in
  Mumbai can produce a small charge

Two caveats worth stating plainly:

1. **Billing must be enabled even to use the free tier.** Cloud Run will not run on a project with
   no billing account. Budget alerts are the safeguard.
2. **Cold starts.** This image carries 267 Python dependencies plus ffmpeg — expect 15–30 seconds
   after idle. Survivable here because uploads go through a WAL queue that retries, so a cold start
   delays a sync rather than losing it. It would not be acceptable for real-time chat.

## Gemini — the part that actually costs money

| Model | Published rate | Per hour of audio |
|---|---|---|
| `gemini-3.5-transcribe-live` (live lane) | $0.005/min audio + $0.004/min text | **~$0.54** |
| `gemini-3.5-transcribe` (batch) | $0.003/min audio | ~$0.18 |
| `gemini-3.1-flash-lite` (backlog lane) | token-priced, very cheap | ~$0.01–0.05 |

At 2 hours of live transcription a day, the live lane alone is **~$32/month**. That dwarfs hosting.

**This is why the two-lane split matters.** The backlog lane already uses `gemini-3.1-flash-lite`
rather than a Live model, so audio that is transcribed after the fact costs a fraction. Keeping
live sessions short and letting the backlog do the bulk is the cheapest correct configuration.

There is a free tier on these models too; check your AI Studio quota before assuming charges.

## Honest totals

| Usage pattern | Realistic monthly |
|---|---|
| Light — 30 min/day, backlog-heavy, Cloud Run | **$0–3** |
| Moderate — 2 h/day, mostly live | **$25–40** |
| Heavy — 6 h/day, all live | **$90–110** |

**Recommendation:** Cloud Run if $0 matters more than a slow first sync; Fly if you want it to feel
instant for a few dollars. In both cases the bill is dominated by transcription, so the lever that
matters is *which lane transcribes what* — not where the server runs.
