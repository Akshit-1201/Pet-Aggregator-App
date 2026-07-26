/// Placeholder written to Secret Manager so the codebase can deploy before a
/// Resend account exists — the CLI refuses to deploy ANY function while a
/// declared secret has no value, even ones that don't use it. Treated as "email
/// is off" rather than firing doomed API calls on every payment.
export const MAIL_DISABLED = "unset";

export const isMailConfigured = (apiKey: string) =>
  apiKey.length > 0 && apiKey !== MAIL_DISABLED;
