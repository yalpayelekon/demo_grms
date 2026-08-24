import 'package:flutter_grems_app/pages/hotel_status/widgets/lighting_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('master power reconciliation waits beyond backend cooldown', () {
    expect(
      postRawCommandRefreshDelay(masterLighting: true),
      const Duration(milliseconds: 15200),
    );
  });

  test('other raw commands retain the short reconciliation delay', () {
    expect(
      postRawCommandRefreshDelay(masterLighting: false),
      const Duration(milliseconds: 700),
    );
  });
}
