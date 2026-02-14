/**
 * Firestore missing-index logging helpers.
 * Keeps index creation links visible when queries fall back or fail.
 */

const FIRESTORE_INDEX_LINK_REGEX =
  /https:\/\/console\.firebase\.google\.com\/[^\s)]+/;

export function extractFirestoreIndexUrl(error: unknown): string | null {
  const message =
    (error as { message?: string } | null)?.message ?? String(error ?? '');
  const match = message.match(FIRESTORE_INDEX_LINK_REGEX);
  return match ? match[0] : null;
}

export function logFirestoreIndexHint(context: string, error: unknown): void {
  const rawMessage =
    (error as { message?: string } | null)?.message ?? String(error ?? '');
  const normalized = rawMessage.toLowerCase();

  const isMissingIndex =
    normalized.includes('requires an index') ||
    normalized.includes('failed-precondition') ||
    normalized.includes('create_composite');

  if (!isMissingIndex) return;

  const indexUrl = extractFirestoreIndexUrl(error);
  if (indexUrl) {
    console.error(`[${context}] Firestore missing index. Create it: ${indexUrl}`);
    return;
  }

  console.error(
    `[${context}] Firestore missing index detected but no direct link was found in error payload.`
  );
}
