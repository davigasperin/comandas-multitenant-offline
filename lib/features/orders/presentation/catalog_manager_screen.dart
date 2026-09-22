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
  int _parseOptionalCents(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '0' || normalized == '0,00') return 0;
    return BrlCurrency.parseToCents(normalized);
  }

  Future<void> _editProduct(CatalogProduct product, List<CatalogCategory> categories) async {
    final name = TextEditingController(text: product.name);
    final price = TextEditingController(text: (product.priceCents / 100).toStringAsFixed(2).replaceAll('.', ','));
    final cost = TextEditingController(text: (product.costCents / 100).toStringAsFixed(2).replaceAll('.', ','));
    final minimumStock = TextEditingController(text: product.minimumStock.toString());
    final stockControlled = ValueNotifier<bool>(product.stockControlled);
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar produto'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nome'), validator: (v) => v == null || v.trim().isEmpty ? 'Informe o nome' : null),
            TextFormField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Preço (R\$)', hintText: 'Ex.: 10,86'),
              validator: (v) { try { BrlCurrency.parseToCents(v ?? ''); return null; } on FormatException catch (e) { return e.message; } },
            ),
            TextFormField(
              controller: cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Custo unitário (R\$)', hintText: '0,00'),
              validator: (v) { try { _parseOptionalCents(v ?? ''); return null; } on FormatException catch (e) { return e.message; } },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: stockControlled,
              builder: (_, value, __) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: value,
                title: const Text('Controlar estoque'),
                onChanged: (next) => stockControlled.value = next ?? false,
              ),
            ),
            TextFormField(
              controller: minimumStock,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Estoque mínimo'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () async {
            if (!formKey.currentState!.validate()) return;
            await ref.read(catalogRepositoryProvider).updateProduct(
              id: product.id,
              name: name.text.trim(),
              priceCents: BrlCurrency.parseToCents(price.text),
              costCents: _parseOptionalCents(cost.text),
              stockControlled: stockControlled.value,
              minimumStock: num.tryParse(minimumStock.text.replaceAll(',', '.')) ?? 0,
              categoryId: product.categoryId,
              available: product.available,
              sortOrder: product.sortOrder,
            );
            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
          }, child: const Text('Salvar')),
        ],
      ),
    );
    if (result == true) ref.invalidate(catalogDataProvider);
  }

  Future<void> _toggleAvailability(CatalogProduct product) async {
    await ref
        .read(catalogRepositoryProvider)
        .setProductAvailability(product.id, !product.available);
    ref.invalidate(catalogDataProvider);
  }

  Future<void> _deleteProduct(CatalogProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir produto?'),
        content: Text('Deseja desativar "${product.name}" do cardápio?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(catalogRepositoryProvider).deleteProduct(product.id);
      ref.invalidate(catalogDataProvider);
    }
  }

  Future<void> _restoreProduct(CatalogProduct product) async {
    await ref.read(catalogRepositoryProvider).restoreProduct(product);
    ref.invalidate(catalogDataProvider);
  }

  Future<void> _newProduct(List<CatalogCategory> categories) async {
    final name = TextEditingController();
    final price = TextEditingController();
    final cost = TextEditingController(text: '0,00');
    final minimumStock = TextEditingController(text: '0');
    final stockControlled = ValueNotifier<bool>(false);
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
                controller: cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Custo unitário (R\$)',
                  hintText: '0,00',
                ),
                validator: (v) {
                  try {
                    _parseOptionalCents(v ?? '');
                    return null;
                  } on FormatException catch (e) {
                    return e.message;
                  }
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: stockControlled,
                builder: (_, value, __) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: value,
                  title: const Text('Controlar estoque'),
                  onChanged: (next) => stockControlled.value = next ?? false,
                ),
              ),
              TextFormField(
                controller: minimumStock,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Estoque mínimo'),
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
              await ref.read(catalogRepositoryProvider).createProduct(
                name: name.text.trim(),
                priceCents: cents,
                costCents: _parseOptionalCents(cost.text),
                stockControlled: stockControlled.value,
                minimumStock: num.tryParse(minimumStock.text.replaceAll(',', '.')) ?? 0,
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
            title: Text(
              product.name,
              style: TextStyle(
                decoration:
                    product.active ? null : TextDecoration.lineThrough,
                color: product.active ? null : Colors.grey,
              ),
            ),
            subtitle: Text(
              '${BrlCurrency.formatCents(product.priceCents)} · custo ${BrlCurrency.formatCents(product.costCents)}'
              '${product.stockControlled ? ' · estoque ${product.stockQuantity} ${product.unit}' : ''}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (product.active) ...[
                  IconButton(
                    tooltip: product.available
                        ? 'Marcar esgotado'
                        : 'Marcar disponível',
                    icon: Icon(
                      product.available
                          ? Icons.check_circle
                          : Icons.do_not_disturb_on,
                      color: product.available ? Colors.green : Colors.orange,
                    ),
                    onPressed: () => _toggleAvailability(product),
                  ),
                  IconButton(
                    tooltip: 'Editar produto',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editProduct(product, value.categories),
                  ),
                  IconButton(
                    tooltip: 'Excluir produto',
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteProduct(product),
                  ),
                ] else ...[
                  TextButton.icon(
                    onPressed: () => _restoreProduct(product),
                    icon: const Icon(Icons.restore),
                    label: const Text('Restaurar'),
                  ),
                ],
              ],
            ),
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
