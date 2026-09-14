import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greenvpn/main.dart';

void main() {
  testWidgets('Home screen shows the Green VPN brand and orb', (tester) async {
    await tester.pumpWidget(const GreenVpnApp());
    await tester.pump();

    expect(find.text('GREEN VPN'), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new_rounded), findsOneWidget);
  });
}
