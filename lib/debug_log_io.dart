import 'dart:io';

void writeDebugLog(String logLine) {
  try {
    final logFile = File(r'c:\Projects\nHabit_traker-main\.cursor\debug.log');
    logFile.writeAsStringSync('$logLine\n', mode: FileMode.append);
  } catch (e) {
    // Silently fail
  }
}
