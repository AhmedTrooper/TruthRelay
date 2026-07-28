class HelpRequest {
  final String id;
  final String kind;
  final String title;
  final String body;
  final String? location;
  final String? contact;
  final String status;
  final String createdAt;
  final String receivedAt;

  const HelpRequest({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.receivedAt,
    this.location,
    this.contact,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'body': body,
        'location': location,
        'contact': contact,
        'status': status,
        'created_at': createdAt,
        'received_at': receivedAt,
      };

  factory HelpRequest.fromJson(Map<String, dynamic> m) => HelpRequest(
        id: m['id'] as String,
        kind: m['kind'] as String,
        title: m['title'] as String,
        body: m['body'] as String,
        location: m['location'] as String?,
        contact: m['contact'] as String?,
        status: m['status'] as String? ?? 'Active',
        createdAt: m['created_at'] as String,
        receivedAt: m['received_at'] as String,
      );
}