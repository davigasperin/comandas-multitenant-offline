import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum OrderStatus { open, sentToKitchen, delivered, closed, canceled }

extension OrderStatusX on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.open:
        return 'Aberta';
      case OrderStatus.sentToKitchen:
        return 'Na cozinha';
      case OrderStatus.delivered:
        return 'Entregue';
      case OrderStatus.closed:
        return 'Fechada';
      case OrderStatus.canceled:
        return 'Cancelada';
    }
  }

  Color get color {
    switch (this) {
      case OrderStatus.open:
        return AppTheme.primary;
      case OrderStatus.sentToKitchen:
        return AppTheme.accent;
      case OrderStatus.delivered:
        return AppTheme.secondary;
      case OrderStatus.closed:
        return Colors.grey.shade600;
      case OrderStatus.canceled:
        return AppTheme.danger;
    }
  }

  static OrderStatus fromString(String value) {
    return OrderStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => OrderStatus.open,
    );
  }
}

class OrderStatusHistoryEntry extends Equatable {
  final String id;
  final String? fromStatus;
  final String toStatus;
  final String? changedBy;
  final DateTime changedAt;

  const OrderStatusHistoryEntry({
    required this.id,
    this.fromStatus,
    required this.toStatus,
    this.changedBy,
    required this.changedAt,
  });

  factory OrderStatusHistoryEntry.fromJson(Map<String, dynamic> json) =>
      OrderStatusHistoryEntry(
        id: json['id'] as String,
        fromStatus: json['from_status'] as String?,
        toStatus: json['to_status'] as String,
        changedBy: json['changed_by'] as String?,
        changedAt: DateTime.parse(json['changed_at'] as String),
      );

  @override
  List<Object?> get props => [id, fromStatus, toStatus, changedBy, changedAt];
}

class OrderItem extends Equatable {
  final String id;
  final String productName;
  final int quantity;
  final int unitPriceCents;
  final String? notes;

  const OrderItem({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.unitPriceCents,
    this.notes,
  });

  double get unitPrice => unitPriceCents / 100.0;
  int get subtotalCents => quantity * unitPriceCents;
  double get subtotal => subtotalCents / 100.0;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: json['id'] as String,
        productName: json['product_name'] as String,
        quantity: json['quantity'] as int,
        unitPriceCents: (json['unit_price_cents'] as num?)?.toInt() ??
            ((json['unit_price'] as num?) != null
                ? ((json['unit_price'] as num) * 100).round()
                : 0),
        notes: json['notes'] as String?,
      );

  @override
  List<Object?> get props =>
      [id, productName, quantity, unitPriceCents, notes];
}

class Order extends Equatable {
  final String id;
  final String tableLabel; // ex.: "Mesa 12" ou "Comanda 034"
  final OrderStatus status;
  final int version;
  final List<OrderItem> items;
  final List<OrderStatusHistoryEntry> history;
  final DateTime openedAt;

  const Order({
    required this.id,
    required this.tableLabel,
    required this.status,
    this.version = 1,
    required this.items,
    this.history = const [],
    required this.openedAt,
  });

  int get totalCents => items.fold(0, (sum, item) => sum + item.subtotalCents);
  double get total => totalCents / 100.0;

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        tableLabel: json['table_label'] as String,
        status: OrderStatusX.fromString(json['status'] as String),
        version: (json['version'] as num?)?.toInt() ?? 1,
        openedAt: DateTime.parse(json['opened_at'] as String),
        items: (json['items'] as List<dynamic>? ?? [])
            .map((i) => OrderItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        history: (json['history'] as List<dynamic>? ?? [])
            .map((h) =>
                OrderStatusHistoryEntry.fromJson(h as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props =>
      [id, tableLabel, status, version, items, history, openedAt];
}
