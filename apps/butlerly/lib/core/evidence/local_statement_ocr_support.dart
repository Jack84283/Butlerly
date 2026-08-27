import 'package:flutter/foundation.dart';

/// Statement OCR currently has a native channel implementation only on iOS.
bool supportsLocalStatementOcr({bool? isWeb, TargetPlatform? platform}) =>
    !(isWeb ?? kIsWeb) &&
    (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
