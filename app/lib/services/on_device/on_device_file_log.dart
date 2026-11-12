import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Append-only log for the on-device transcription path, written next to `wals.json`.
///
/// The failure banner in the app says only that a run failed. The in-app log buffer is in memory
/// and empty after a restart, so a failure that needs investigating has usually lost its evidence
/// by the time anyone looks. Writing to disk keeps it.
class OnDeviceFileLog {
  OnDeviceFileLog._();

  static const fileName = 'on_device.log';
  static const maxBytes = 256 * 1024;

  static Future<void> write(String message) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      if (await file.exists() && await file.length() > maxBytes) {
        final tail = await file.readAsString();
        await file.writeAsString(tail.substring(tail.length ~/ 2));
      }
      await file.writeAsString('${DateTime.now().toIso8601String()} $message\n',
          mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging must never break transcription.
    }
  }

  static Future<void> error(String where, Object error, [StackTrace? stack]) =>
      write('ERROR $where: $error${stack == null ? '' : '\n$stack'}');
}
