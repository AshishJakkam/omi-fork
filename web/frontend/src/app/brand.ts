/**
 * Brand constants for the marketing site.
 *
 * One place to rename. The product name appears nowhere else on the landing page, so settling the
 * brand is a one-file edit rather than a search across components.
 *
 * Omi is MIT licensed, which permits a commercial fork. That licence requires the copyright notice
 * to travel with the software, so /licenses must stay reachable from the footer.
 */
export const brand = {
  /** Placeholder until the name is chosen. */
  name: 'Recall',
  tagline: 'A memory for your whole life, not just your notes.',
  description:
    'An always-on assistant that listens, remembers, and answers questions about your own conversations. Runs on hardware you choose, with a backend you control.',
  email: 'hello@example.com',
} as const;
