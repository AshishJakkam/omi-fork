# End-to-end encryption: what it would take, and what it would cost you

Written because "can we be like WhatsApp?" is a fair question and the honest answer is
*yes, but it deletes a feature*. This is a design note, not an implementation plan.

## The constraint, stated plainly

Every AI feature in this app runs **on the server, over plaintext**:

| Feature | Where it runs | Needs plaintext? |
|---|---|---|
| Conversation summary | `backend/utils/prompts.py` | yes |
| Memory extraction | `utils/prompts.py:14` — *"You are an expert memory curator…"* | yes |
| Chat over your history | server | yes |
| Goals / open loops | `utils/open_loops/prompts.py` | yes |

If the server cannot decrypt a transcript, it cannot summarise it, extract memories from it, or
answer questions across it. That is not a configuration choice; it is what "the server cannot read
the data" means.

So true E2EE and server-side AI are **mutually exclusive**. Anyone claiming both is either
encrypting at rest and calling it E2EE, or decrypting briefly on the server and hoping nobody asks.

## Three architectures

### A. Encrypted at rest — what this deployment does today

The server holds the key, decrypts to process, re-encrypts to store. `ENCRYPTION_SECRET` is that
key.

- **Protects against:** a stolen disk, a database dump, a curious hosting provider reading files.
- **Does not protect against:** the operator (you), or anyone who obtains the key.
- **AI works:** fully.

### B. E2EE storage with client-side AI — the "WhatsApp model"

The phone encrypts before upload; the server stores ciphertext and never holds a key; the phone
decrypts and calls the model directly with the user's own API key.

- **Protects against:** the operator, the host, and a subpoena to the server.
- **Costs you:** every AI call moves to the device. Reprocessing history server-side becomes
  impossible. Background summarisation while the app is closed stops working — iOS will not let a
  suspended app run inference reliably.
- **Half of this already exists:** the Gemini Live socket calls Google **directly from the phone**
  with the user's key. Extending that to summaries is the natural path.

### C. E2EE with no AI

Store ciphertext, never process it. Private, but it is a voice recorder, not an assistant.

## What real E2EE would require

Not a flag — a protocol:

1. **Key generation on device**, never transmitted. Ideally in the Secure Enclave.
2. **A key exchange** if a user has several devices, or the data is unreadable on the second one.
3. **Client-side inference** for every feature above, which means shipping a model or calling a
   provider from the phone.
4. **A recovery story.** Lose the phone, lose the data — unless you add key escrow, which
   reintroduces exactly the third party E2EE was meant to remove.
5. **Verification.** Without a published protocol and an audit, "E2EE" is marketing.

## The honest marketing position today

What this deployment can truthfully claim:

- ✅ **Omi never sees your data.** Self-hosting removes them from the path.
- ✅ Transcripts are **encrypted at rest**; the key never leaves your server.
- ✅ Audio can stay **entirely on the phone** if you choose on-device transcription.
- ❌ Not end-to-end encrypted: the operator can read transcripts.
- ❌ Not anonymous: Google sees Firebase and Gemini traffic; the host sees the data at rest.
- ❌ Not audited.

That is a strong and defensible position — "we removed the third party that had no reason to exist"
is a better story than a vague E2EE claim you cannot substantiate.

## If you want to offer E2EE later

It is a **second product tier**, not a change to this one: a build where the server is a blind blob
store and all inference happens on the phone. Same backend, different client. Users who want
maximum privacy lose cloud summaries; users who want the assistant accept the trade. Shipping both
is honest; claiming one is the other is not.
