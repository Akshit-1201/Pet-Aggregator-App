/** What account deletion must physically remove for one uid, kept apart from
 *  deleteMyAccount so it can be unit-tested — a missed prefix here is personal
 *  data (or an ID document) that silently outlives the account. */

/** Cloud Storage prefixes owned by [uid] whose content dies with the account.
 *  Must track every upload path in the app (and storage.rules). Post photos
 *  are deliberately absent: posts are kept, anonymised, so their photos stay. */
export function personalStoragePrefixes(uid: string): string[] {
  if (!uid) throw new Error("uid required"); // "" would make these bucket-wide
  return [
    `users/${uid}/`, // avatar
    `pets/${uid}_`, // pets/{uid}_{millis}.jpg
    `homestays/${uid}/`, // listing photos
    `brands/${uid}/`, // brand logo + product photos
    `verification/${uid}/`, // KYC ID documents
  ];
}

/** Subcollections under users/{uid}. Firestore does not cascade a document
 *  delete to its subcollections, so each must be emptied explicitly. */
export const PERSONAL_SUBCOLLECTIONS: readonly string[] = ["fcmTokens", "blocked"];
