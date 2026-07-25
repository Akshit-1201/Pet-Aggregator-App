import {HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

/**
 * Creating a Razorpay Route linked account for a pro or host.
 *
 * **Raw bank details and PAN never touch Firestore.** They arrive in the
 * callable, go straight to Razorpay, and only the returned account id plus a
 * masked last-4 is persisted. Storing an account number would make Firestore a
 * far more attractive target than it already is, for no product benefit — the
 * partner never needs to read it back, and Razorpay is the system of record.
 *
 * Nothing is ever logged from the payload for the same reason.
 */

export type BankDetails = {
  name: string;
  email: string;
  pan: string;
  accountNumber: string;
  ifsc: string;
  beneficiaryName: string;
};

const IFSC_RE = /^[A-Z]{4}0[A-Z0-9]{6}$/;
const PAN_RE = /^[A-Z]{5}[0-9]{4}[A-Z]$/;

export function readBankDetails(data: unknown): BankDetails {
  const d = (data ?? {}) as Record<string, unknown>;
  const s = (k: string) => String(d[k] ?? "").trim();

  const details: BankDetails = {
    name: s("name"),
    email: s("email").toLowerCase(),
    pan: s("pan").toUpperCase(),
    accountNumber: s("accountNumber").replace(/\s/g, ""),
    ifsc: s("ifsc").toUpperCase(),
    beneficiaryName: s("beneficiaryName"),
  };

  // Validated here rather than only in the app: a callable is reachable without
  // the app, and a malformed account number means money going nowhere.
  if (!details.name) throw new HttpsError("invalid-argument", "name-required");
  if (!details.email.includes("@")) throw new HttpsError("invalid-argument", "email-invalid");
  if (!PAN_RE.test(details.pan)) throw new HttpsError("invalid-argument", "pan-invalid");
  if (!IFSC_RE.test(details.ifsc)) throw new HttpsError("invalid-argument", "ifsc-invalid");
  if (details.accountNumber.length < 6 || !/^\d+$/.test(details.accountNumber)) {
    throw new HttpsError("invalid-argument", "account-number-invalid");
  }
  if (!details.beneficiaryName) {
    throw new HttpsError("invalid-argument", "beneficiary-name-required");
  }
  return details;
}

type RazorpayRoute = {
  accounts: {create: (p: object) => Promise<{id: string}>};
  stakeholders: {create: (accountId: string, p: object) => Promise<{id: string}>};
  products: {
    requestProductConfiguration: (accountId: string, p: object) => Promise<{id: string}>;
    edit: (accountId: string, productId: string, p: object) => Promise<unknown>;
  };
};

/**
 * Route onboarding is three calls: the account, a stakeholder (the person
 * behind it, with their PAN), then the `route` product configured with the
 * settlement bank account. Razorpay then runs its own checks — the account is
 * not immediately payable, which is why status starts as `pending`.
 */
export async function createLinkedAccount(
  rzp: RazorpayRoute,
  uid: string,
  d: BankDetails,
): Promise<{accountId: string}> {
  const account = await rzp.accounts.create({
    email: d.email,
    phone: "",
    type: "route",
    legal_business_name: d.name,
    business_type: "individual",
    contact_name: d.name,
    profile: {category: "services", subcategory: "other"},
    reference_id: uid, // ties the Razorpay account back to the Pawgo user
  });

  await rzp.stakeholders.create(account.id, {
    name: d.beneficiaryName,
    email: d.email,
    kyc: {pan: d.pan},
  });

  const product = await rzp.products.requestProductConfiguration(account.id, {
    product_name: "route",
    tnc_accepted: true,
  });

  await rzp.products.edit(account.id, product.id, {
    settlements: {
      account_number: d.accountNumber,
      ifsc_code: d.ifsc,
      beneficiary_name: d.beneficiaryName,
    },
    tnc_accepted: true,
  });

  return {accountId: account.id};
}

/** Persists only what is safe to keep. */
export async function savePayoutAccount(uid: string, accountId: string, d: BankDetails) {
  await admin.firestore().collection("payoutAccounts").doc(uid).set({
    uid,
    razorpayAccountId: accountId,
    // Enough for a partner to recognise which account they gave us, and
    // useless to anyone who steals it.
    bankLast4: d.accountNumber.slice(-4),
    ifsc: d.ifsc,
    beneficiaryName: d.beneficiaryName,
    status: "pending", // Razorpay has to run its own checks before it is payable
    createdAt: Date.now(),
    updatedAt: Date.now(),
    error: "",
  });
  logger.info("payout account created", {uid, accountId});
}
