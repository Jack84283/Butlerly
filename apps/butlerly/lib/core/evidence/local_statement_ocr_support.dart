import 'package:flutter/foundation.dart';

/// Statement image OCR is available through the local native adapters.
bool supportsLocalStatementOcr({bool? isWeb, TargetPlatform? platform}) =>
    !(isWeb ?? kIsWeb) &&
    ((platform ?? defaultTargetPlatform) == TargetPlatform.iOS ||
        (platform ?? defaultTargetPlatform) == TargetPlatform.android);
