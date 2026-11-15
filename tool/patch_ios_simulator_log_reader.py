#!/usr/bin/env python3
"""CI-only backport of Flutter iOS simulator VM Service discovery race fix.

Upstream: https://github.com/flutter/flutter/commit/c3ed85ef987759ee54a6bce275490cde2a238dc1
The pinned SDK predates that fix. Fail closed if upstream anchors change.
Never modify Butlerly application sources or the pinned SDK version.
"""
import os
from pathlib import Path

root = os.environ.get("FLUTTER_ROOT")
if not root:
    raise SystemExit("FLUTTER_ROOT must identify the installed Flutter SDK.")
source = Path(root) / "packages/flutter_tools/lib/src/ios/simulators.dart"
original = source.read_text(encoding="utf-8")
if "await logReader._ready.future;" in original:
    print("Flutter simulator log-readiness fix already present.")
    raise SystemExit(0)

replacements = [
  [
    "  final _logReaders = <IOSApp?, DeviceLogReader>{};",
    "  final _logReaders = <IOSApp?, _IOSSimulatorLogReader>{};"
  ],
  [
    "  DeviceLogReader getLogReader({covariant IOSApp? app, bool includePastLogs = false}) {",
    "  _IOSSimulatorLogReader getLogReader({covariant IOSApp? app, bool includePastLogs = false}) {"
  ],
  [
    "    if (debuggingOptions.debuggingEnabled) {\n      vmServiceDiscovery = ProtocolDiscovery.vmService(\n        getLogReader(app: package),",
    "    if (debuggingOptions.debuggingEnabled) {\n      final _IOSSimulatorLogReader logReader = getLogReader(app: package);\n      vmServiceDiscovery = ProtocolDiscovery.vmService(\n        logReader,"
  ],
  [
    "        logger: globals.logger,\n      );\n    }\n\n    // Launch the updated application in the simulator.",
    "        logger: globals.logger,\n      );\n      // Wait for the log reader before launching; otherwise the VM Service\n      // URL printed on launch can be lost to a startup race.\n      const warningDelay = Duration(seconds: 30);\n      final timer = Timer(warningDelay, () {\n        globals.printError(\n          'The iOS simulator log stream has not started after 30 seconds.',\n        );\n      });\n      await logReader._ready.future;\n      timer.cancel();\n    }\n\n    // Launch the updated application in the simulator."
  ],
  [
    "  late final _linesController = StreamController<String>.broadcast(\n    onListen: _start,\n    onCancel: _stop,\n  );\n\n  @override",
    "  late final _linesController = StreamController<String>.broadcast(\n    onListen: _start,\n    onCancel: _stop,\n  );\n\n  /// Completes when this log stream emits its initial header or exits.\n  var _ready = Completer<void>();\n\n  @override"
  ],
  [
    "  Future<void> _start() async {\n    // Unified logging iOS 11 and greater (introduced in iOS 10).",
    "  Future<void> _start() async {\n    // Each new listener must wait for its own log stream.\n    _ready = Completer<void>();\n    final Completer<void> ready = _ready;\n    // Unified logging iOS 11 and greater (introduced in iOS 10)."
  ],
  [
    "      _deviceProcess?.stdout.transform(utf8LineDecoder).listen(_onUnifiedLoggingLine);",
    "      _deviceProcess?.stdout.transform(utf8LineDecoder).listen((String line) {\n        if (!ready.isCompleted) {\n          ready.complete();\n        }\n        _onUnifiedLoggingLine(line);\n      });"
  ],
  [
    "      _deviceProcess?.exitCode.whenComplete(() {\n        if (_linesController.hasListener) {",
    "      _deviceProcess?.exitCode.whenComplete(() {\n        if (!ready.isCompleted) {\n          ready.complete();\n        }\n        if (_linesController.hasListener) {"
  ]
]

patched = original
for before, after in replacements:
    matches = patched.count(before)
    if matches != 1:
        raise SystemExit(
            f"Refusing SDK patch: anchor occurs {matches} times: "
            f"{before.splitlines()[0]}"
        )
    patched = patched.replace(before, after, 1)

if patched.count("await logReader._ready.future;") != 1:
    raise SystemExit("SDK patch result does not contain the readiness wait.")
temporary = source.with_name(source.name + ".butlerly-tmp")
try:
    temporary.write_text(patched, encoding="utf-8")
    temporary.replace(source)
finally:
    temporary.unlink(missing_ok=True)
print("Applied Flutter upstream iOS simulator log-readiness fix to CI SDK.")
