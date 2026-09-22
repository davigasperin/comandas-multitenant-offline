import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/formatters/currency_formatter.dart';
import '../../../core/network/providers.dart';

class ManagementScreen extends ConsumerStatefulWidget {
  const ManagementScreen({super.key});

  @override
  ConsumerState<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends ConsumerState<ManagementScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _entitlements = const {};
  Map<String, dynamic> _margin = const {};
  List<Map<String, dynamic>> _expenses = const [];
  List<Map<String, dynamic>> _stock = const [];
  List<Map<String, dynamic>> _employees = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(managementRepositoryProvider);
      final entitlements = await repository.getEntitlements();
      final features = Map<String, dynamic>.from(
          entitlements['features'] as Map? ?? const {});
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, 1);
      final results = await Future.wait<dynamic>([
        repository.getStock(),
        repository.getEmployees(),
        if (features['accounts_payable'] == true)
          repository.getExpenses()
        else
          Future.value(<Map<String, dynamic>>[]),
        if (features['profit_margin'] == true)
          repository.getProfitMargin(from: from, to: now)
        else
          Future.value(<String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _entitlements = entitlements;
        _stock = results[0] as List<Map<String, dynamic>>;
        _employees = results[1] as List<Map<String, dynamic>>;
        _expenses = results[2] as List<Map<String, dynamic>>;
        _margin = results[3] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  bool get _isPro => _entitlements['plan'] == 'pro';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestão do restaurante'),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Financeiro', icon: Icon(Icons.account_balance_wallet_outlined)),
              Tab(text: 'Estoque', icon: Icon(Icons.inventory_2_outlined)),
              Tab(text: 'Margem', icon: Icon(Icons.insights_outlined)),
              Tab(text: 'Funcionários', icon: Icon(Icons.people_outline)),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : TabBarView(
                    children: [
                      _isPro ? _expensesTab() : const _ProRequired(),
                      _stockTab(),
                      _isPro ? _marginTab() : const _ProRequired(),
                      _employeesTab(),
                    ],
                  ),
      ),
    );
  }

  Widget _expensesTab() {
    if (_expenses.isEmpty) return const Center(child: Text('Nenhuma conta a pagar cadastrada.'));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _expenses.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, index) {
        final expense = _expenses[index];
        final due = DateTime.tryParse(expense['due_date']?.toString() ?? '');
        return ListTile(
          leading: Icon(
            expense['status'] == 'paid' ? Icons.check_circle : Icons.schedule,
            color: expense['status'] == 'overdue' ? Colors.red : null,
          ),
          title: Text(expense['description']?.toString() ?? 'Despesa'),
          subtitle: Text(
            '${expense['category']?['name'] ?? 'Sem categoria'} · '
            '${due == null ? '' : DateFormat('dd/MM/yyyy').format(due.toLocal())}',
          ),
          trailing: Text(BrlCurrency.formatCents(
              (expense['balance_cents'] as num?)?.toInt() ?? 0)),
        );
      },
    );
  }

  Widget _stockTab() {
    if (_stock.isEmpty) return const Center(child: Text('Nenhum produto com controle de estoque.'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _stock.length,
      itemBuilder: (_, index) {
        final product = _stock[index];
        final quantity = num.tryParse(product['stock_quantity'].toString()) ?? 0;
        final minimum = num.tryParse(product['minimum_stock'].toString()) ?? 0;
        return Card(
          child: ListTile(
            leading: Icon(Icons.inventory_2, color: quantity <= minimum ? Colors.orange : Colors.green),
            title: Text(product['name']?.toString() ?? 'Produto'),
            subtitle: Text('Mínimo: $minimum ${product['unit'] ?? ''}'),
            trailing: Text('$quantity ${product['unit'] ?? ''}'),
          ),
        );
      },
    );
  }

  Widget _marginTab() {
    final cards = <(String, String, Color)>[
      ('Receita líquida', 'net_revenue_cents', Colors.blue),
      ('CMV', 'cmv_cents', Colors.orange),
      ('Lucro bruto', 'gross_profit_cents', Colors.teal),
      ('Despesas', 'expenses_cents', Colors.red),
      ('Resultado operacional', 'operating_result_cents', Colors.green),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Mês atual', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...cards.map((card) => Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: card.$3.withValues(alpha: .15), child: Icon(Icons.attach_money, color: card.$3)),
                title: Text(card.$1),
                trailing: Text(
                  BrlCurrency.formatCents((_margin[card.$2] as num?)?.toInt() ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            )),
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text('Resultado estimado. O eixo das despesas está configurado por competência.'),
        ),
      ],
    );
  }

  Widget _employeesTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _employees.length,
      itemBuilder: (_, index) {
        final employee = _employees[index];
        return ListTile(
          leading: CircleAvatar(child: Text((employee['name']?.toString() ?? '?')[0].toUpperCase())),
          title: Text(employee['name']?.toString() ?? 'Funcionário'),
          subtitle: Text('${employee['email']} · ${employee['role']}'),
          trailing: Icon(employee['active'] == true ? Icons.check_circle : Icons.block,
              color: employee['active'] == true ? Colors.green : Colors.grey),
        );
      },
    );
  }
}

class _ProRequired extends StatelessWidget {
  const _ProRequired();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_outlined, size: 52),
            SizedBox(height: 12),
            Text('Recurso disponível no plano Pro', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('A validação também é aplicada pelo servidor.'),
          ],
        ),
      ),
    );
  }
}
