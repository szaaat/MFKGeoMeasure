import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test fake async', () {
    fakeAsync((async) {
      bool fired = false;
      Future.delayed(const Duration(seconds: 1), () => fired = true);
      async.elapse(const Duration(seconds: 1));
      expect(fired, isTrue);
    });
  });
}
