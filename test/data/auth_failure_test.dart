import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';

void main() {
  test('AuthFailure.fromCode maps Firebase codes to friendly types', () {
    expect(AuthFailure.fromCode('wrong-password').type, AuthFailureType.invalidCredentials);
    expect(AuthFailure.fromCode('email-already-in-use').type, AuthFailureType.emailInUse);
    expect(AuthFailure.fromCode('weak-password').type, AuthFailureType.weakPassword);
    expect(AuthFailure.fromCode('anything-else').type, AuthFailureType.unknown);
  });
}
