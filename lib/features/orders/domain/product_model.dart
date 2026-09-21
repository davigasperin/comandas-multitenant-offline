import 'package:equatable/equatable.dart';

class Product extends Equatable {
  final String id;
  final String name;
  final int priceCents;

  const Product({
    required this.id,
    required this.name,
    required this.priceCents,
  });

  double get price => priceCents / 100.0;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        priceCents: (json['price_cents'] as num?)?.toInt() ??
            ((json['price'] as num?) != null
                ? ((json['price'] as num) * 100).round()
                : 0),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price_cents': priceCents,
      };

  @override
  List<Object?> get props => [id, name, priceCents];
}
