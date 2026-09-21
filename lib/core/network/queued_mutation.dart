import 'package:equatable/equatable.dart';

enum MutationStatus { pending, syncing, failed, synced }

class QueuedMutation extends Equatable {
  final String id;
  final String idempotencyKey;
  final String method;
  final String path;
  final Map<String, dynamic>? body;
  final String tenantId;
  final String userId;
  final DateTime createdAt;
  final MutationStatus status;
  final int retryCount;
  final String? lastError;

  const QueuedMutation({
    required this.id,
    required this.idempotencyKey,
    required this.method,
    required this.path,
    this.body,
    required this.tenantId,
    required this.userId,
    required this.createdAt,
    this.status = MutationStatus.pending,
    this.retryCount = 0,
    this.lastError,
  });

  QueuedMutation copyWith({
    String? id,
    String? idempotencyKey,
    String? method,
    String? path,
    Map<String, dynamic>? body,
    String? tenantId,
    String? userId,
    DateTime? createdAt,
    MutationStatus? status,
    int? retryCount,
    String? lastError,
  }) {
    return QueuedMutation(
      id: id ?? this.id,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      method: method ?? this.method,
      path: path ?? this.path,
      body: body ?? this.body,
      tenantId: tenantId ?? this.tenantId,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'idempotency_key': idempotencyKey,
      'method': method,
      'path': path,
      'body': body,
      'tenant_id': tenantId,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'status': status.name,
      'retry_count': retryCount,
      'last_error': lastError,
    };
  }

  factory QueuedMutation.fromJson(Map<String, dynamic> json) {
    return QueuedMutation(
      id: json['id'] as String,
      idempotencyKey: json['idempotency_key'] as String,
      method: json['method'] as String,
      path: json['path'] as String,
      body: json['body'] != null ? Map<String, dynamic>.from(json['body'] as Map) : null,
      tenantId: json['tenant_id'] as String,
      userId: json['user_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: MutationStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => MutationStatus.pending,
      ),
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      lastError: json['last_error'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        idempotencyKey,
        method,
        path,
        body,
        tenantId,
        userId,
        createdAt,
        status,
        retryCount,
        lastError,
      ];
}
