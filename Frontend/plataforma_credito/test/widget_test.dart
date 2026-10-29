import 'package:flutter_test/flutter_test.dart';
import 'package:plataforma_credito/main.dart';

void main() {
  testWidgets('La aplicación inicia correctamente', (WidgetTester tester) async {
    await tester.pumpWidget(const PlataformaCreditoApp());

    expect(find.byType(PlataformaCreditoApp), findsOneWidget);
  });
}