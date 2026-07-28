enum OutboxKind { bulletin, request }

class OutboxEntry {
  final int localId;
  final OutboxKind kind;
  final String payload;
  final String status;
  final int attempts;
  final String? lastError;
  final String createdAt;

  const OutboxEntry({
    required this.localId,
    required this.kind,
    required this.payload,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.lastError,
  });

  OutboxEntry copyWith({
    int? localId,
    OutboxKind? kind,
    String? payload,
    String? status,
    int? attempts,
    String? lastError,
    String? createdAt,
  }) =>
      OutboxEntry(
        localId: localId ?? this.localId,
        kind: kind ?? this.kind,
        payload: payload ?? this.payload,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'local_id': localId,
        'kind': kind.name,
        'payload': payload,
        'status': status,
        'attempts': attempts,
        'last_error': lastError,
        'created_at': createdAt,
      };

  factory OutboxEntry.fromJson(Map<String, dynamic> m) => OutboxEntry(
        localId: m['local_id'] as int,
        kind: OutboxKind.values.firstWhere((e) => e.name == m['kind']),
        payload: m['payload'] as String,
        status: m['status'] as String,
        attempts: m['attempts'] as int,
        lastError: m['last_error'] as String?,
        createdAt: m['created_at'] as String,
      );
}