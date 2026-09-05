import 'orbit_error.dart';

class OrbitResponse {
  final String id;
  final String type;
  final String action;
  final bool success;
  final Map<String, dynamic>? payload;
  final OrbitError? error;

  const OrbitResponse({
    required this.id,
    this.type = 'response',
    required this.action,
    required this.success,
    this.payload,
    this.error,
  });

  factory OrbitResponse.fromJson(Map<String, dynamic> json) {
    return OrbitResponse(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'response',
      action: json['action'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      payload: json['payload'] as Map<String, dynamic>?,
      error: json['error'] != null
          ? OrbitError.fromJson(json['error'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'action': action,
        'success': success,
        if (payload != null) 'payload': payload,
        if (error != null) 'error': error!.toJson(),
      };

  @override
  String toString() =>
      'OrbitResponse(id: $id, action: $action, success: $success, payload: $payload, error: $error)';
}
