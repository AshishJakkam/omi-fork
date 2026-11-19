import type { Metadata } from 'next';
import Link from 'next/link';
import { brand } from '../brand';

export const metadata: Metadata = {
  title: 'Licences & attribution',
  description: 'Open-source licences for software included in this product.',
};

/**
 * The MIT licence requires its copyright notice and permission text to accompany the software.
 * That makes this page a legal obligation rather than a courtesy, so it must stay reachable from
 * the footer of every public page.
 */
const notices = [
  {
    name: 'Omi',
    holder: 'Based Hardware Contributors',
    year: '2024',
    url: 'https://github.com/BasedHardware/omi',
    note: 'The application, firmware and backend this product is built on.',
  },
];

const MIT_TEXT = `MIT License

Copyright (c) 2024 Based Hardware Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.`;

export default function LicensesPage() {
  return (
    <div className="min-h-screen bg-black text-white">
      <div className="mx-auto max-w-3xl px-6 py-16 md:py-24">
        <Link href="/" className="text-xs text-white/40 transition hover:text-white/70">
          ← Back
        </Link>
        <h1 className="mt-6 text-3xl font-semibold tracking-tight">Licences &amp; attribution</h1>
        <p className="mt-4 text-sm leading-relaxed text-white/60">
          {brand.name} is built on open-source software. Where a licence requires attribution, it is
          reproduced in full below.
        </p>

        <div className="mt-12 space-y-10">
          {notices.map((n) => (
            <section key={n.name}>
              <div className="flex flex-wrap items-baseline gap-x-3">
                <h2 className="text-base font-medium">{n.name}</h2>
                <span className="font-mono text-xs text-indigo-400">MIT</span>
              </div>
              <p className="mt-2 text-sm text-white/60">{n.note}</p>
              <p className="mt-1 text-xs text-white/40">
                © {n.year} {n.holder} —{' '}
                <a href={n.url} className="underline underline-offset-2 hover:text-white/70">
                  source
                </a>
              </p>
              <pre className="mt-4 overflow-x-auto rounded-lg border border-white/10 bg-white/[0.03] p-5 text-[11px] leading-relaxed text-white/60">
                {MIT_TEXT}
              </pre>
            </section>
          ))}
        </div>

        <section className="mt-12 border-t border-white/10 pt-8">
          <h2 className="text-base font-medium">Trademarks are not covered</h2>
          <p className="mt-2 text-sm leading-relaxed text-white/60">
            The MIT licence above covers software, not branding. The names, logos and marks of the
            upstream project belong to their owners and are not used as this product&apos;s identity.
          </p>
        </section>
      </div>
    </div>
  );
}
