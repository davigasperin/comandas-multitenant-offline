import 'package:equatable/equatable.dart';

class CatalogCategory extends Equatable {
  final String id;
  final String name;
  final int sortOrder;
  final bool active;
  final String productionArea;

  const CatalogCategory({required this.id, required this.name, required this.sortOrder, required this.active, required this.productionArea});

  factory CatalogCategory.fromJson(Map<String, dynamic> json) => CatalogCategory(
    id: json['id'].toString(),
    name: json['name'].toString(),
    sortOrder: json['sort_order'] as int? ?? 0,
    active: json['active'] as bool? ?? true,
    productionArea: json['production_area'] as String? ?? 'kitchen',
  );

  @override
  List<Object?> get props => [id, name, sortOrder, active, productionArea];
}

class CatalogProduct extends Equatable {
  final String id;
  final String name;
  final int priceCents;
  final String? categoryId;
  final bool active;
  final bool available;
  final int sortOrder;

  const CatalogProduct({required this.id, required this.name, required this.priceCents, required this.active, required this.available, required this.sortOrder, this.categoryId});

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
    id: json['id'].toString(),
    name: json['name'].toString(),
    priceCents: json['price_cents'] as int,
    categoryId: json['categoryId'] as String?,
    active: json['active'] as bool? ?? true,
    available: json['available'] as bool? ?? true,
    sortOrder: json['sort_order'] as int? ?? 0,
  );

  @override
  List<Object?> get props => [id, name, priceCents, categoryId, active, available, sortOrder];
}

class DiningTableModel extends Equatable {
  final String id;
  final String label;
  final int capacity;
  final int x;
  final int y;
  final int width;
  final int height;
  final String shape;
  final bool active;
  final bool occupied;
  final String? activeOrderId;

  const DiningTableModel({required this.id, required this.label, required this.capacity, required this.x, required this.y, required this.width, required this.height, required this.shape, required this.active, required this.occupied, this.activeOrderId});

  factory DiningTableModel.fromJson(Map<String, dynamic> json) => DiningTableModel(
    id: json['id'].toString(),
    label: json['label'].toString(),
    capacity: json['capacity'] as int? ?? 4,
    x: json['pos_x'] as int? ?? json['position_x'] as int? ?? 0,
    y: json['pos_y'] as int? ?? json['position_y'] as int? ?? 0,
    width: json['width'] as int? ?? 120,
    height: json['height'] as int? ?? 120,
    shape: json['shape'] as String? ?? 'square',
    active: json['active'] as bool? ?? true,
    occupied: json['is_occupied'] as bool? ?? false,
    activeOrderId: (json['active_order'] as Map<String, dynamic>?)?['id'] as String?,
  );

  @override
  List<Object?> get props => [id, label, capacity, x, y, width, height, shape, active, occupied, activeOrderId];
}
