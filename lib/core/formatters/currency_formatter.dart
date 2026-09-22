import 'package:intl/intl.dart';

class BrlCurrency {
  BrlCurrency._();

  static final NumberFormat _formatter =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);

  static int parseToCents(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.startsWith('-')) {
      throw const FormatException('Informe um preço maior que zero.');
    }

    final match = RegExp(r'^(\d+)([,.](\d{1,2}))?$').firstMatch(normalized);
    if (match == null) {
      throw const FormatException('Use um valor como 10,86.');
    }

    final reais = int.parse(match.group(1)!);
    final decimal = match.group(3) ?? '';
    final centavos = decimal.isEmpty
        ? 0
        : int.parse(decimal.length == 1 ? '${decimal}0' : decimal);
    final total = reais * 100 + centavos;

    if (total <= 0) {
      throw const FormatException('Informe um preço maior que zero.');
    }

    return total;
  }

  static String formatCents(int cents) => _formatter.format(cents / 100);
}
