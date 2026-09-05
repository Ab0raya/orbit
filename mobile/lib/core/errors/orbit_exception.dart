class OrbitException implements Exception {
  final String message;
  final String? code;
  final dynamic cause;

  const OrbitException(this.message, {this.code, this.cause});

  @override
  String toString() => code != null ? '[$code] $message' : message;
}

class OrbitProtocolException extends OrbitException {
  const OrbitProtocolException(super.message, {super.code, super.cause});
}

class OrbitConnectionException extends OrbitException {
  const OrbitConnectionException(super.message, {super.cause})
      : super(code: 'CONNECTION_FAILED');
}

class OrbitTimeoutException extends OrbitException {
  const OrbitTimeoutException(super.message)
      : super(code: 'TIMEOUT');
}
