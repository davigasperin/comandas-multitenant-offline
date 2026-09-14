import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';

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

class OrderItem extends Equatable {
  final String id;
  final String productName;
  final int quantity;
  final double unitPrice;
  final String? notes;

  const OrderItem({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.notes,
  });

  double get subtotal => quantity * unitPrice;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: json['id'] as String,
        productName: json['product_name'] as String,
        quantity: json['quantity'] as int,
        unitPrice: (json['unit_price'] as num).toDouble(),
        notes: json['notes'] as String?,
      );

  @override
  List<Object?> get props => [id, productName, quantity, unitPrice, notes];
}

class Order extends Equatable {
  final String id;
  final String tableLabel; // ex.: "Mesa 12" ou "Comanda 034"
  final OrderStatus status;
  final List<OrderItem> items;
  final DateTime openedAt;

  const Order({
    required this.id,
    required this.tableLabel,
    required this.status,
    required this.items,
    required this.openedAt,
  });

  double get total => items.fold(0, (sum, item) => sum + item.subtotal);

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        tableLabel: json['table_label'] as String,
        status: OrderStatusX.fromString(json['status'] as String),
        openedAt: DateTime.parse(json['opened_at'] as String),
        items: (json['items'] as List<dynamic>? ?? [])
            .map((i) => OrderItem.fromJson(i as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props => [id, tableLabel, status, items, openedAt];
}
