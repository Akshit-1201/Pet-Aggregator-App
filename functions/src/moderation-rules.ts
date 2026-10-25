/** Pure moderation rules — no Firebase imports, so they unit-test cleanly. */

export type Likelihood =
  "UNKNOWN" | "VERY_UNLIKELY" | "UNLIKELY" | "POSSIBLE" | "LIKELY" | "VERY_LIKELY";

const RANK: Record<string, number> = {
  UNKNOWN: 0, VERY_UNLIKELY: 1, UNLIKELY: 2, POSSIBLE: 3, LIKELY: 4, VERY_LIKELY: 5,
};

export type SafeSearch = {adult?: string | null; violence?: string | null;
  racy?: string | null; medical?: string | null; spoof?: string | null};

/**
 * Which categories make a photo unacceptable. Thresholds are deliberately
 * conservative about false positives: this is a pet app, and a vet photo
 * (medical) or a dog in a bath (racy at POSSIBLE) must not vanish. Racy only
 * counts at VERY_LIKELY; medical and spoof never block.
 */
export function moderationVerdict(s: SafeSearch): {blocked: boolean; reasons: string[]} {
  const reasons: string[] = [];
  const atLeast = (v: string | null | undefined, level: Likelihood) =>
    (RANK[String(v ?? "UNKNOWN")] ?? 0) >= RANK[level];
  if (atLeast(s.adult, "LIKELY")) reasons.push(`adult:${s.adult}`);
  if (atLeast(s.violence, "LIKELY")) reasons.push(`violence:${s.violence}`);
  if (atLeast(s.racy, "VERY_LIKELY")) reasons.push(`racy:${s.racy}`);
  return {blocked: reasons.length > 0, reasons};
}

/** The uploader's uid, from the path conventions storage.rules enforces. */
export function uploaderOf(path: string): string | null {
  let m = path.match(/^users\/([^/]+)\/avatar\.jpg$/);
  if (m) return m[1];
  m = path.match(/^(?:homestays|brands)\/([^/]+)\/[^/]+$/);
  if (m) return m[1];
  m = path.match(/^(?:pets|posts)\/([^/_]+)_[^/]+$/);
  if (m) return m[1];
  return null;
}

/** Public photo paths. Anything else (KYC documents, unknown paths) is skipped. */
export function isModeratedPath(path: string): boolean {
  return /^(users\/[^/]+\/avatar\.jpg|(?:homestays|brands)\/[^/]+\/[^/]+|pets\/[^/]+|posts\/[^/]+)$/.test(path);
}
