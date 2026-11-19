import type { Metadata } from 'next';
import Link from 'next/link';
import {
  ArrowRight,
  BatteryCharging,
  Brain,
  Check,
  Lock,
  Mic,
  Search,
  Server,
  ShieldCheck,
  Sparkles,
} from 'lucide-react';
import { brand } from './brand';

export const metadata: Metadata = {
  title: `${brand.name} — ${brand.tagline}`,
  description: brand.description,
};

/** Sections that make the same claims the product can actually keep. */
const capabilities = [
  {
    icon: Mic,
    title: 'It listens, continuously',
    body: 'A small wearable captures the conversations you are already having. No prompts, no unlocking a phone, no deciding what is worth remembering.',
  },
  {
    icon: Brain,
    title: 'It builds memory, not notes',
    body: 'Conversations become summaries, and summaries become facts about your life — the people you met, what you decided, what you promised.',
  },
  {
    icon: Search,
    title: 'You can ask it anything',
    body: '“What did we agree about pricing?” is answered from your own history, with the conversation it came from cited underneath.',
  },
];

const privacy = [
  {
    icon: Server,
    title: 'Your backend, not ours',
    body: 'Transcription, storage and search run on a server you deploy. There is no vendor in the middle of your conversations.',
  },
  {
    icon: Lock,
    title: 'Encrypted at rest',
    body: 'Transcripts are encrypted with a key that never leaves your deployment. A stolen disk is not a stolen diary.',
  },
  {
    icon: ShieldCheck,
    title: 'Audio can stay on the phone',
    body: 'Transcribe on the device and only text is ever uploaded — or stream to a model you have your own key for.',
  },
];

const steps = [
  {
    step: '01',
    title: 'Wear it',
    body: 'Clip it on in the morning. It runs all day on a charge and does not need your phone nearby.',
  },
  {
    step: '02',
    title: 'It transcribes and summarises',
    body: 'Speech becomes text on the device or in your own backend, then into a summary with the people and decisions pulled out.',
  },
  {
    step: '03',
    title: 'Ask later',
    body: 'Weeks later, ask what was said. Answers come from your history, not the internet.',
  },
];

const faqs = [
  {
    q: 'Is this the same as Omi?',
    a: 'It is built on Omi, which is open source under the MIT licence. That licence permits commercial use and modification; the copyright notice ships with the app. The name, logo and brand are not covered by that licence and are not used here.',
  },
  {
    q: 'Where does my audio go?',
    a: 'Wherever you point it. Transcribe on the device and only text leaves the phone. Or connect a model provider with your own key, in which case audio goes straight from your phone to that provider under their terms — not through us.',
  },
  {
    q: 'Can you read my conversations?',
    a: 'On a self-hosted deployment, the operator of that server can. That is the honest trade of running your own backend: you remove the vendor, and you take on the responsibility. We do not claim end-to-end encryption, because server-side summaries and search are incompatible with it.',
  },
  {
    q: 'What does it cost to run?',
    a: 'Hosting is small — a free tier covers a single user. The real cost is the model that transcribes and summarises, which scales with how much you talk rather than with the number of users.',
  },
];

export default function MarketingHome() {
  return (
    <div className="bg-black text-white">
      {/* Hero */}
      <section className="relative overflow-hidden border-b border-white/10">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_top,rgba(99,102,241,0.18),transparent_60%)]"
        />
        <div className="relative mx-auto max-w-5xl px-6 pb-24 pt-20 md:pb-32 md:pt-28">
          <p className="mb-6 inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-3 py-1 text-xs text-white/70">
            <Sparkles className="h-3.5 w-3.5" />
            Open source, self-hostable
          </p>
          <h1 className="max-w-3xl text-4xl font-semibold leading-[1.1] tracking-tight md:text-6xl">
            {brand.tagline}
          </h1>
          <p className="mt-6 max-w-2xl text-lg leading-relaxed text-white/70">{brand.description}</p>
          <div className="mt-10 flex flex-wrap items-center gap-4">
            <Link
              href="#how"
              className="inline-flex items-center gap-2 rounded-lg bg-white px-5 py-3 text-sm font-medium text-black transition hover:bg-white/90"
            >
              See how it works
              <ArrowRight className="h-4 w-4" />
            </Link>
            <Link
              href="/licenses"
              className="inline-flex items-center gap-2 rounded-lg border border-white/20 px-5 py-3 text-sm font-medium text-white/80 transition hover:border-white/40 hover:text-white"
            >
              Read the licence
            </Link>
          </div>
          <dl className="mt-16 grid max-w-2xl grid-cols-2 gap-6 border-t border-white/10 pt-8 sm:grid-cols-3">
            {[
              { k: 'Runs on', v: 'Your server' },
              { k: 'Transcribes', v: 'On device or BYO key' },
              { k: 'Storage', v: 'Encrypted at rest' },
            ].map(({ k, v }) => (
              <div key={k}>
                <dt className="text-xs uppercase tracking-wider text-white/40">{k}</dt>
                <dd className="mt-1 text-sm font-medium text-white/90">{v}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      {/* Capabilities */}
      <section className="mx-auto max-w-5xl px-6 py-20 md:py-28">
        <h2 className="max-w-2xl text-2xl font-semibold tracking-tight md:text-3xl">
          Three things it does that a notes app cannot
        </h2>
        <div className="mt-12 grid gap-6 md:grid-cols-3">
          {capabilities.map(({ icon: Icon, title, body }) => (
            <div
              key={title}
              className="rounded-xl border border-white/10 bg-white/[0.03] p-6 transition hover:border-white/20"
            >
              <Icon className="h-5 w-5 text-indigo-400" />
              <h3 className="mt-4 text-base font-medium">{title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-white/60">{body}</p>
            </div>
          ))}
        </div>
      </section>

      {/* How it works */}
      <section id="how" className="border-y border-white/10 bg-white/[0.02]">
        <div className="mx-auto max-w-5xl px-6 py-20 md:py-28">
          <h2 className="text-2xl font-semibold tracking-tight md:text-3xl">How it works</h2>
          <div className="mt-12 grid gap-8 md:grid-cols-3">
            {steps.map(({ step, title, body }) => (
              <div key={step}>
                <div className="font-mono text-xs text-indigo-400">{step}</div>
                <h3 className="mt-3 text-base font-medium">{title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-white/60">{body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Privacy */}
      <section className="mx-auto max-w-5xl px-6 py-20 md:py-28">
        <h2 className="max-w-2xl text-2xl font-semibold tracking-tight md:text-3xl">
          Privacy, stated precisely
        </h2>
        <p className="mt-4 max-w-2xl text-sm leading-relaxed text-white/60">
          Most products in this category say “private” and mean “we promise”. This one is private
          because of where the data physically goes.
        </p>
        <div className="mt-12 grid gap-6 md:grid-cols-3">
          {privacy.map(({ icon: Icon, title, body }) => (
            <div key={title} className="rounded-xl border border-white/10 p-6">
              <Icon className="h-5 w-5 text-emerald-400" />
              <h3 className="mt-4 text-base font-medium">{title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-white/60">{body}</p>
            </div>
          ))}
        </div>
        <p className="mt-8 max-w-2xl text-xs leading-relaxed text-white/40">
          What we do not claim: this is not end-to-end encrypted, and it is not anonymous. Summaries
          and search run on a server, which means that server can read plaintext. That is a
          deliberate trade, documented in full rather than hidden in a policy.
        </p>
      </section>

      {/* FAQ */}
      <section className="border-t border-white/10 bg-white/[0.02]">
        <div className="mx-auto max-w-3xl px-6 py-20 md:py-28">
          <h2 className="text-2xl font-semibold tracking-tight md:text-3xl">Questions</h2>
          <div className="mt-10 divide-y divide-white/10">
            {faqs.map(({ q, a }) => (
              <details key={q} className="group py-5">
                <summary className="flex cursor-pointer list-none items-center justify-between text-sm font-medium text-white/90">
                  {q}
                  <span className="text-white/30 transition group-open:rotate-45">+</span>
                </summary>
                <p className="mt-3 text-sm leading-relaxed text-white/60">{a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="mx-auto max-w-5xl px-6 py-20 md:py-28">
        <div className="rounded-2xl border border-white/10 bg-gradient-to-b from-indigo-500/10 to-transparent p-10 text-center md:p-16">
          <h2 className="text-2xl font-semibold tracking-tight md:text-3xl">
            Bring your own backend. Keep your own memory.
          </h2>
          <p className="mx-auto mt-4 max-w-xl text-sm leading-relaxed text-white/60">
            Deploy in an afternoon, point the app at it, and the limits someone else set stop
            applying.
          </p>
          <div className="mt-8 flex flex-wrap justify-center gap-3">
            <Link
              href="#how"
              className="inline-flex items-center gap-2 rounded-lg bg-white px-5 py-3 text-sm font-medium text-black transition hover:bg-white/90"
            >
              Get started
              <ArrowRight className="h-4 w-4" />
            </Link>
          </div>
          <ul className="mx-auto mt-8 flex max-w-md flex-wrap justify-center gap-x-6 gap-y-2 text-xs text-white/50">
            {['No vendor in the path', 'On-device option', 'MIT licensed core'].map((item) => (
              <li key={item} className="inline-flex items-center gap-1.5">
                <Check className="h-3.5 w-3.5 text-emerald-400" />
                {item}
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-white/10">
        <div className="mx-auto flex max-w-5xl flex-col gap-4 px-6 py-10 text-xs text-white/40 md:flex-row md:items-center md:justify-between">
          <p>
            © {new Date().getFullYear()} {brand.name}. Built on the open-source Omi project.
          </p>
          <nav className="flex flex-wrap gap-x-6 gap-y-2">
            <Link href="/licenses" className="transition hover:text-white/70">
              Licences &amp; attribution
            </Link>
            <a href={`mailto:${brand.email}`} className="transition hover:text-white/70">
              Contact
            </a>
          </nav>
        </div>
      </footer>
    </div>
  );
}
