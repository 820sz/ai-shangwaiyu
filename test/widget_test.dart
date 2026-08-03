import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/app.dart';

void main() {
  testWidgets('App starts correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const ReadFlowApp());
    // 验证底部三栏导航存在
    expect(find.text('输入'), findsOneWidget);
    expect(find.text('输出'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
