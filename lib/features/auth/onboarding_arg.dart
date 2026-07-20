// Carried via go_router `extra` from LocationScreen to the three onboarding
// destination screens so they know they're in the signup funnel (show a skip,
// exit to Home). Screens reached by other routes get extra == null.
class OnboardingArg {
  final bool fromOnboarding;
  const OnboardingArg({this.fromOnboarding = false});
}
