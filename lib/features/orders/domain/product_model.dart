import 'package:equatable/equatable.dart';

class Product extends Equatable {
  final String id;
  final String name;
  final double price;

  const Product({
    required this.id,
    required this.name,
    required this.price,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
      );

  @override
  List<Object?> get props => [id, name, price];
}
