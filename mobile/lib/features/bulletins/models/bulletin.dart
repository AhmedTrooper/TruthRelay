class Bulletin {
  final String id;
  final String kind;
  final String title;
  final String body;
  final String? sha256;
  final String status;
  final String? moderatorId;
  final String? moderatorName;
  final String? signatureB64;
  final String createdAt;
  final String receivedAt;

  const Bulletin({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.receivedAt,
    this.sha256,
    this.moderatorId,
    this.moderatorName,
    this.signatureB64,
  });

  bool get isVerified => moderatorName != null && moderatorName!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'body': body,
        'sha256': sha256,
        'status': status,
        'moderator_id': moderatorId,
        'moderator_name': moderatorName,
        'signature_b64': signatureB64,
        'created_at': createdAt,
        'received_at': receivedAt,
      };

  factory Bulletin.fromJson(Map<String, dynamic> m) => Bulletin(
        id: m['id'] as String,
        kind: m['kind'] as String,
        title: m['title'] as String,
        body: m['body'] as String,
        sha256: m['sha256'] as String?,
        status: m['status'] as String? ?? 'Active',
        moderatorId: m['moderator_id'] as String?,
        moderatorName: m['moderator_name'] as String?,
        signatureB64: m['signature_b64'] as String?,
        createdAt: m['created_at'] as String,
        receivedAt: m['received_at'] as String,
      );
}