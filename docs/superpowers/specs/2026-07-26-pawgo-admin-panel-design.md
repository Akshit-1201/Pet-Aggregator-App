# Pawgo Phase 12: Admin & Moderation Panel — Design

> **Status:** approved design (2026-07-26). The launch-critical slice of `plan.md` Phase 12. Built on the live Firebase backend — **no mock data**. Two parts: a Flutter **KYC submission** slice (prerequisite), then the **Next.js admin panel** that reviews it.

## Goal

An internal web dashboard for staff to run the platform: approve partner verification, action reported content, and manage users. `plan.md:166` calls these three modules a **launch prerequisite** — a customer-facing UGC + marketplace app cannot open to the public without them.

Two queues are already filling up with nothing reading them:
- `reports` — filed by users since 2026-07-25, invisible to everyone.
- `verified` on `pros`/`homestays` — now trustworthy (clients can't write it) but grantable only by hand in the Firebase Console.

## Decisions settled before building

| Decision | Choice | Why |
|---|---|---|
| Admin sign-in | **Google SSO + `adminRoles` allowlist + custom claim** | `plan.md` wanted domain-restricted SSO; there is no Workspace domain, and an allowlist gives the same control. No passwords to manage. |
| Verification depth | **Real KYC documents** | Reviewing a listing alone is human judgement, not identity proof. The submission flow is built first. |
| Privileged writes | **Next.js server actions (Admin SDK)** | `plan.md` said Cloud Functions. The property that matters — *the browser never writes admin data directly* — holds either way. Server actions avoid a network hop and cold starts. Ops the **mobile app also calls** stay Cloud Functions. |
| Location | **`/admin` in this repo** | `firestore.rules`, `functions/` and the panel change together; cross-repo coordination would be a standing tax. |

## The KYC gap this closes

`plan.md` assumed a `verificationRequests` collection and "submitted documents from Storage". **Neither existed.** Nothing in the Flutter app ever submitted one, and `storage.rules` covered only avatars, pet photos and homestay photos. So Part A builds the submission side before the panel has anything to review.

---

## Part A — Flutter: KYC submission

### `verificationRequests/{uid}`

Doc id is the applicant's uid — one active request per person, matching how `pros/{uid}` and `homestays/{uid}` are keyed. Re-applying after a rejection overwrites.

```
uid          : string   (== doc id)
kind         : 'pro' | 'homestay'
status       : 'pending' | 'approved' | 'rejected'
docPaths     : string[]  Storage OBJECT PATHS, not download URLs (see below)
applicantName: string    denormalised so the queue lists without N reads
area         : string    denormalised
submittedAt  : int millis
reviewedAt   : int millis  (0 until reviewed)
reviewedBy   : string      admin email, '' until reviewed
reason       : string      rejection reason shown back to the applicant
```

**`docPaths`, not download URLs.** Every other image in Pawgo stores a `getDownloadURL()` link, which carries a token and is effectively a public URL. That is acceptable for a pet photo and **unacceptable for an ID document**. Storage keeps KYC objects unreadable by clients entirely; the panel mints short-lived **signed URLs** server-side when a reviewer opens the request.

### Storage: `verification/{uid}/{file}`

```
allow read:  if false;                    // clients NEVER read these
allow write: if request.auth.uid == uid   // owner uploads only
             && size < 5MB
             && contentType.matches('image/.*');
```

`read: if false` is the important line and the deliberate difference from every other Storage path in the project, which use `read: if request.auth != null`. An applicant's passport must not be fetchable by any signed-in user who can guess a path. The Admin SDK bypasses rules, so the panel still reads them.

### Firestore rules

```
match /verificationRequests/{uid} {
  allow read:   if request.auth.uid == uid;          // applicant sees own status
  allow create, update: if request.auth.uid == uid
        && request.resource.data.status == 'pending' // can't self-approve
        && !diff.affectedKeys().hasAny(['reviewedAt','reviewedBy','reason']);
  allow delete: if false;
}
```

### UI

Pro-setup and Host-setup gain a **"Get verified"** step: pick 1–3 images, upload, submit. Status is surfaced back on the same screen — `pending` / `approved` / `rejected` with the reason. Verification stays **optional**; an unverified pro can still list (they simply read "not yet Pawgo-verified", which is already true today).

---

## Part B — Next.js admin panel

### Stack

Next.js (App Router) + TypeScript + Tailwind, `firebase-admin` server-side, `firebase/auth` client-side for the Google popup only. No component library — the surface is small and a dependency would outweigh it.

### Auth chain

1. Google popup → Firebase ID token.
2. Server action verifies the token, looks the email up in `adminRoles`.
3. Not listed → rejected, nothing is set.
4. Listed → custom claims `{admin: true, role}` set, **session cookie** issued (`createSessionCookie`, 8h).
5. `middleware.ts` guards every route except `/login`.

Claims are set from the allowlist on each sign-in, so revoking access is one Firestore edit.

### `adminRoles/{email}`

```
email : string   (== doc id, lowercased)
role  : 'superAdmin' | 'moderator' | 'support'
addedBy, addedAt
```

Rules: `read, write: if false` — Admin SDK only. A client that could write this could grant itself admin.

### RBAC matrix

| Capability | superAdmin | moderator | support |
|---|:--:|:--:|:--:|
| View queues & users | ✅ | ✅ | ✅ |
| Approve / reject verification | ✅ | ✅ | ❌ |
| Action reports (dismiss / remove) | ✅ | ✅ | ❌ |
| Suspend / reactivate a user | ✅ | ✅ | ❌ |
| Manage admin roles | ✅ | ❌ | ❌ |
| View audit log | ✅ | ✅ | ✅ |

Enforced **server-side in every action**, never only in the UI.

### `auditLogs/{autoId}`

```
actorEmail, actorRole, action, targetType, targetId,
reason, at : int millis
```

Append-only; rules deny clients entirely. Every mutating action writes one **in the same code path as the mutation** — an action that can't be logged doesn't happen.

### Server actions

| Action | Role | Effect |
|---|---|---|
| `approveVerification(uid, kind)` | moderator+ | request → `approved`, sets `verified: true` on `pros`/`homestays` |
| `rejectVerification(uid, reason)` | moderator+ | request → `rejected` with reason |
| `resolveReport(id, action, reason)` | moderator+ | dismiss, or remove the reported content |
| `setUserSuspended(uid, bool, reason)` | moderator+ | `admin.auth().updateUser({disabled})` |
| `setAdminRole(email, role)` | superAdmin | writes `adminRoles` |

Suspension uses **Firebase Auth `disabled`**, not a Firestore flag: it invalidates tokens at the source, so a suspended user is locked out on next refresh rather than relying on every client honouring a flag.

### Out of scope for v1

Bookings/disputes, payouts, community management, broadcast, analytics/KPIs beyond queue counts — all post-launch per `plan.md`. Deployment (Vercel vs Firebase Hosting) is a separate decision; v1 targets local `next dev` against the live project.

## Verification

- A `support` admin is denied every mutation, server-side.
- Approving a request flips `verified` and the pro shows the badge in the app.
- A removed post disappears from the Community feed.
- A suspended user cannot sign in.
- Every mutation leaves an audit entry.
