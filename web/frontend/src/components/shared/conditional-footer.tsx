'use client';

import { usePathname } from 'next/navigation';
import Footer from './footer';

/**
 * Routes that carry their own chrome.
 *
 * The marketing landing page and the licence page are a standalone site: they bring their own
 * header and footer, so the app's product header and store footer would otherwise appear above and
 * below them. Listing them here is cheaper than restructuring the root layout, which every app
 * page depends on.
 */
const SELF_CHROMED = ['/licenses'];

function isSelfChromed(pathname: string | null): boolean {
  if (!pathname) return false;
  return pathname === '/' || SELF_CHROMED.some((p) => pathname === p || pathname.startsWith(`${p}/`));
}

export default function ConditionalFooter() {
  const pathname = usePathname();
  const isConversationPage = pathname?.includes('/conversations');

  if (isConversationPage || isSelfChromed(pathname)) {
    return null;
  }

  return <Footer />;
}
