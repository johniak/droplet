/// True only inside the integration-test run: the app then skips system
/// permission dialogs, which a widget-driver cannot tap.
const kE2E = bool.fromEnvironment('E2E');
