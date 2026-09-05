class OrbitRequest {
  final String id;
  final String type;
  final String action;
  final Map<String, dynamic> payload;

  const OrbitRequest({
    required this.id,
    this.type = 'request',
    required this.action,
    this.payload = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'action': action,
        'payload': payload,
      };

  factory OrbitRequest.fromJson(Map<String, dynamic> json) {
    return OrbitRequest(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'request',
      action: json['action'] as String,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }

  @override
  String toString() => 'OrbitRequest(id: $id, action: $action, payload: $payload)';
}
