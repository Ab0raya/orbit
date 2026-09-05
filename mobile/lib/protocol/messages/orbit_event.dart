class OrbitEvent {
  final String type;
  final String event;
  final Map<String, dynamic> payload;

  const OrbitEvent({
    this.type = 'event',
    required this.event,
    this.payload = const {},
  });

  factory OrbitEvent.fromJson(Map<String, dynamic> json) {
    return OrbitEvent(
      type: json['type'] as String? ?? 'event',
      event: json['event'] as String? ?? '',
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'event': event,
        'payload': payload,
      };

  @override
  String toString() => 'OrbitEvent(event: $event, payload: $payload)';
}
