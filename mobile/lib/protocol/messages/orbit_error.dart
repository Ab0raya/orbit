class OrbitError {
  final String code;
  final String message;

  const OrbitError({
    required this.code,
    required this.message,
  });

  factory OrbitError.fromJson(Map<String, dynamic> json) {
    return OrbitError(
      code: json['code'] as String? ?? 'UNKNOWN_ERROR',
      message: json['message'] as String? ?? 'An unknown error occurred.',
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
      };

  @override
  String toString() => 'OrbitError(code: $code, message: $message)';
}
