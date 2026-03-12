import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piples_sprite_tool_mobile/main.dart';

void main() {
  testWidgets('App başlatma testi', (WidgetTester tester) async {
    // Widget ağacını oluştur
    await tester.pumpWidget(const MyApp(cameras: []));

    // Başlık metnini kontrol et
    expect(find.text('🎮 Piples Sprite Tool'), findsOneWidget);
    expect(find.text('📷 Fotoğraf Çek'), findsOneWidget);
    expect(find.text('🖼 Galeriden Seç'), findsOneWidget);
  });
}
