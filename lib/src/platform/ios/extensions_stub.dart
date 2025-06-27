// Stub for non-iOS platforms
extension BoolExt on bool {
  dynamic toNSNumber() => null;
}

extension IntExt on int {
  dynamic toNSNumber() => null;
}

extension StringExt on String {
  /// Stub for NSURL conversion
  dynamic toNSURL() => null;

  /// Stub for NSData conversion
  dynamic toNSDataUTF8() => null;
}
