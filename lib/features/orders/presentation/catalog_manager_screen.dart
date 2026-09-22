import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/network/providers.dart';
import '../domain/catalog_models.dart';
import 'order_detail_screen.dart';

final catalogDataProvider = FutureProvider.autoDispose((ref) async {
  final repository = ref.watch(catalogRepositoryProvider);
  return (
    categories: await repository.categories(),
    products: await repository.products(),
    tables: await repository.tables(),
  );
});

class CatalogManagerScreen extends ConsumerStatefulWidget {
  const CatalogManagerScreen({super.key});

  @override
  ConsumerState<CatalogManagerScreen> createState() => _CatalogManagerScreenState();
}

class _CatalogManagerScreenState extends ConsumerState<CatalogManagerScreen> {
  Future<void> _newProduct(List<CatalogCategory> categories) async {
    final name = TextEditingController();
    final price = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Novo produto'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Informe o nome' : null,
              ),
              TextFormField(
                controller: price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Preço (R\$)',
                  hintText: 'Ex.: 10,86',
                ),
                validator: (v) {
                  try {
                    BrlCurrency.parseToCents(v ?? '');
                    return null;
                  } on FormatException catch (e) {
                    return e.message;
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final cents = BrlCurrency.parseToCents(price.text);
              await ref.read(catalogRepositoryProvider).save(
                'products',
                {
                  'name': name.text.trim(),
                  'price_cents': cents,
                },
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (result == true) ref.invalidate(catalogDataProvider);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(catalogDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo e mesas')),
      body: data.when(loading: () => const Center(child: CircularProgressIndicator()), error: (e, _) => Center(child: Text('Erro: $e')), data: (value) => ListView(padding: const EdgeInsets.all(16), children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Produtos', style: Theme.of(context).textTheme.titleLarge), IconButton(tooltip: 'Novo produto', onPressed: () => _newProduct(value.categories), icon: const Icon(Icons.add))]),
        ...value.products.map(
          (product) => ListTile(
            title: Text(product.name),
            subtitle: Text(BrlCurrency.formatCents(product.priceCents)),
            trailing:
                Text(product.available ? 'Disponível' : 'Indisponível'),
          ),
        ),
        const SizedBox(height: 16),
        Text('Mapa de mesas', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        SizedBox(height: 420, child: Stack(children: value.tables.map((table) => Positioned(left: table.x.toDouble(), top: table.y.toDouble(), child: GestureDetector(onTap: table.activeOrderId == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: table.activeOrderId!))), child: Container(width: table.width.toDouble(), height: table.height.toDouble(), alignment: Alignment.center, decoration: BoxDecoration(color: table.occupied ? Colors.orange.shade200 : Colors.green.shade100, border: Border.all(color: Colors.black54), shape: table.shape == 'circle' ? BoxShape.circle : BoxShape.rectangle), child: Text(table.label))))).toList())),
      ])),
    );
  }
}
