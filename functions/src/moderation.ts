import {onObjectFinalized} from "firebase-functions/v2/storage";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {ImageAnnotatorClient} from "@google-cloud/vision";
import {type SafeSearch, isModeratedPath, moderationVerdict, uploaderOf} from "./moderation-rules";

/**
 * Automatic image moderation for everything users upload publicly.
 *
 * Every new avatar, pet, post and homestay photo is run through Cloud Vision
 * SafeSearch. A photo that is likely adult, violent or gory is DELETED at
 * once — the app's image widget then shows its placeholder — and recorded in
 * `moderationFlags` for the admin team to review. A flagged avatar is also
 * cleared from the user's profile.
 *
 * KYC documents (verification/) are excluded: they are never shown to other
 * users, and an ID photo is exactly what a classifier mislabels.
 *
 * Fails OPEN: if Vision is unreachable or not enabled on the project, the
 * photo stays up and the error is logged. A moderation outage must not make
 * every upload in the app fail.
 *
 * Owner setup: enable the Cloud Vision API on pet-aggregator-app
 * (console.cloud.google.com → APIs & Services → Enable APIs → "Cloud Vision
 * API"). Billing is already on; the first 1,000 images a month are free.
 */

let vision: ImageAnnotatorClient | null = null;

export const moderateUploadedImage = onObjectFinalized(
  {region: "asia-south1", memory: "512MiB"},
  async (event) => {
    const {name: path, bucket, contentType} = event.data;
    if (!path || !isModeratedPath(path)) return;
    if (!String(contentType ?? "").startsWith("image/")) return;

    let safe: SafeSearch;
    try {
      vision ??= new ImageAnnotatorClient();
      const [res] = await vision.safeSearchDetection(`gs://${bucket}/${path}`);
      safe = (res.safeSearchAnnotation ?? {}) as SafeSearch;
    } catch (e) {
      logger.error("moderation: Vision call failed — leaving image up (fail-open)", {path, error: e});
      return;
    }

    const verdict = moderationVerdict(safe);
    if (!verdict.blocked) return;

    const uid = uploaderOf(path);
    logger.warn("moderation: removing flagged upload", {path, uid, reasons: verdict.reasons});
    try {
      await admin.storage().bucket(bucket).file(path).delete({ignoreNotFound: true});
    } catch (e) {
      logger.error("moderation: delete failed", {path, error: e});
    }
    try {
      await admin.firestore().collection("moderationFlags").add({
        path, uid, reasons: verdict.reasons, safeSearch: safe,
        action: "deleted", reviewed: false, createdAt: Date.now(),
      });
      // A deleted avatar would leave a dead link on the profile; clear it so
      // the app falls back to the initial-letter avatar.
      if (uid && path === `users/${uid}/avatar.jpg`) {
        await admin.firestore().collection("users").doc(uid).set({photoUrl: ""}, {merge: true});
      }
    } catch (e) {
      logger.error("moderation: bookkeeping failed", {path, error: e});
    }
  });
