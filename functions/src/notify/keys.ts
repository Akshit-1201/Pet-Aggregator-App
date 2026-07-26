/** Deterministic dedupe keys. The key becomes the notification document id, so
 *  a re-delivered trigger re-writes the same path instead of notifying twice.
 *  Keys are scoped per user (records live under notifications/{uid}/items), so
 *  a scenario sent to two people can safely share one key. */

export const bookingKey = (scenario: string, bookingId: string) => `${scenario}_${bookingId}`;
export const chatKey = (chatId: string) => `chat_${chatId}`;
export const postKey = (postId: string) => `post_${postId}`;
export const matchKey = (otherUid: string) => `WOOF1_${otherUid}`;
export const verdictKey = (scenario: string, reviewedAt: number) =>
  `${scenario}_${reviewedAt}`;

/** IST calendar month. Bucketing in UTC would move the boundary by 5.5 hours
 *  and let a 1am-IST run on the 1st count as the previous month. */
export const monthKey = (scenario: string, at: number) => {
  const ist = new Date(at + 5.5 * 3600 * 1000);
  const mm = String(ist.getUTCMonth() + 1).padStart(2, "0");
  return `${scenario}_${ist.getUTCFullYear()}-${mm}`;
};
