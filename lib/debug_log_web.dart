// import 'dart:html' as html;

void writeDebugLog(String logLine) {
  // print('DEBUG_LOG: $logLine');
  // Avoid OOM by not sending HTTP requests
  try {
    print('DEBUG_LOG: $logLine');
  } catch (e) {
    // ignore
  }
}
