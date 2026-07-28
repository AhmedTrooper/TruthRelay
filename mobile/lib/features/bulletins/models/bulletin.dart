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

  /// Result of the last local Ed25519 signature check against the
  /// moderator's registered pubkey. `null` means the verification
  /// has not been performed yet (e.g. server-supplied bulletin where
  /// the server already verified); `true` means the local check
  /// passed; `false` means the local check failed — the bulletin
  /// is **not** VERIFIED and the UI should show "Quarantined".
  ///
  /// This field is computed locally — never trusted from a peer's
  /// word, never copied from another Bulletin instance.
  final bool? signatureVerified;

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
    this.signatureVerified,
  });

  bool get isVerified => moderatorName != null && moderatorName!.isNotEmpty;

  /// `true` only when we have *both* a moderator name (server has
  /// registered this key) and a locally-verified Ed25519 signature.
  /// Anything else — missing pubkey, tampered payload, unknown mod —
  /// is treated as not VERIFIED so the UI cannot show the green badge
  /// for a tampered bulletin.
  bool get isVerifiedLocally =>
      signatureVerified == true &&
      moderatorName != null &&
      moderatorName!.isNotEmpty;

  Bulletin copyWith({
    String? id,
    String? kind,
    String? title,
    String? body,
    String? sha256,
    String? status,
    String? moderatorId,
    String? moderatorName,
    String? signatureB64,
    String? createdAt,
    String? receivedAt,
    bool? signatureVerified,
    bool resetSignatureVerified = false,
  }) =>
      Bulletin(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        title: title ?? this.title,
        body: body ?? this.body,
        sha256: sha256 ?? this.sha256,
        status: status ?? this.status,
        moderatorId: moderatorId ?? this.moderatorId,
        moderatorName: moderatorName ?? this.moderatorName,
        signatureB64: signatureB64 ?? this.signatureB64,
        createdAt: createdAt ?? this.createdAt,
        receivedAt: receivedAt ?? this.receivedAt,
        signatureVerified:
            resetSignatureVerified ? null : signatureVerified ?? this.signatureVerified,
      );

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
        // Stored locally so the UI can show the badge across app
        // restarts without re-running the verification dance — but
        // always overwritten by the next `upsertMany` call, so a
        // tampered bulletin can never launder a `true` result through
        // the box.
        'signature_verified': signatureVerified,
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
        // Always re-derive from the on-disk value if present so the
        // boolean survives a round-trip — but it is *never* trusted
        // when the bulletin comes from a peer: the next `upsertMany`
        // call will overwrite it with a fresh verification result.
        signatureVerified: m['signature_verified'] as bool?,
      );
}