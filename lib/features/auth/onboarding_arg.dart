// Carried via go_router `extra` from LocationScreen to the three onboarding
// destination screens so they know they're in the signup funnel (show a skip,
// exit to Home). Screens reached by other routes get extra == null.
class OnboardingArg {
  final bool fromOnboarding;
  const OnboardingArg({this.fromOnboarding = false});
}

/// Carried to SignupScreen after a first-time Google/Apple sign-in: the
/// account exists but has no profile yet. The provider has verified the email
/// and there is no password, so signup only collects the name and role.
class SocialSignupArg {
  final String name, email;
  const SocialSignupArg({required this.name, required this.email});
}
