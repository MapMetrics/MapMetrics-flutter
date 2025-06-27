import 'package:objective_c/objective_c.dart' as objc;

extension BoolExt on bool {
  objc.NSNumber toNSNumber() => objc.NSNumber.numberWithBool_(this ? 1 : 0);
}

extension IntExt on int {
  objc.NSNumber toNSNumber() => objc.NSNumber.numberWithInt_(this);
}

extension StringExt on String {
  /// Convert to a [NSURL].
  objc.NSURL? toNSURL() => objc.NSURL.URLWithString_(toNSString());

  /// Convert to a [NSData].
  objc.NSData? toNSDataUTF8() =>
      toNSString().dataUsingEncoding_(4); // nsUTF8StringEncoding = 4
}
