import 'package:flutter_test/flutter_test.dart';
import 'package:comandas_app/core/formatters/currency_formatter.dart';

void main() {
  test('converte valor em reais para centavos sem ponto flutuante', () {
    expect(BrlCurrency.parseToCents('10,86'), 1086);
    expect(BrlCurrency.parseToCents('10.86'), 1086);
    expect(BrlCurrency.parseToCents('10'), 1000);
    expect(BrlCurrency.parseToCents('0,01'), 1);
  });

  test('rejeita valores monetários inválidos', () {
    expect(() => BrlCurrency.parseToCents(''), throwsFormatException);
    expect(() => BrlCurrency.parseToCents('0'), throwsFormatException);
    expect(() => BrlCurrency.parseToCents('-10,00'), throwsFormatException);
    expect(() => BrlCurrency.parseToCents('10,999'), throwsFormatException);
    expect(() => BrlCurrency.parseToCents('dez reais'), throwsFormatException);
  });
}
