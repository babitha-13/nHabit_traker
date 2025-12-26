import 'package:just_audio/just_audio.dart';

/// Sound helper utility for playing audio feedback
/// Handles all sound effects for user interactions
class SoundHelper {
  static final SoundHelper _instance = SoundHelper._internal();
  factory SoundHelper() => _instance;
  SoundHelper._internal();

  AudioPlayer? _completionPlayer;
  AudioPlayer? _stepCounterPlayer;
  AudioPlayer? _playButtonPlayer;
  AudioPlayer? _stopButtonPlayer;

  bool _isInitialized = false;
  bool _soundsEnabled = true;

  /// Initialize sound players
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _completionPlayer = AudioPlayer();
      _stepCounterPlayer = AudioPlayer();
      _playButtonPlayer = AudioPlayer();
      _stopButtonPlayer = AudioPlayer();

      // Load sound files
      await _completionPlayer!.setAsset('assets/audios/completion.mp3');
      await _stepCounterPlayer!.setAsset('assets/audios/step_counter.mp3');
      await _playButtonPlayer!.setAsset('assets/audios/play_button.mp3');
      await _stopButtonPlayer!.setAsset('assets/audios/stop_button.mp3');

      _isInitialized = true;
    } catch (e) {
      // If sound files don't exist, continue without sounds
      // This allows the app to work even if sound files are missing
      print('SoundHelper: Could not initialize sounds: $e');
      _isInitialized = false;
    }
  }

  /// Enable or disable sounds
  void setSoundsEnabled(bool enabled) {
    _soundsEnabled = enabled;
  }

  /// Play completion sound (for binary ticks and target reached)
  Future<void> playCompletionSound() async {
    if (!_soundsEnabled || !_isInitialized) return;
    try {
      await _completionPlayer?.seek(Duration.zero);
      await _completionPlayer?.play();
    } catch (e) {
      print('SoundHelper: Error playing completion sound: $e');
    }
  }

  /// Play step counter sound (for quantitative increments)
  Future<void> playStepCounterSound() async {
    if (!_soundsEnabled || !_isInitialized) return;
    try {
      await _stepCounterPlayer?.seek(Duration.zero);
      await _stepCounterPlayer?.play();
    } catch (e) {
      print('SoundHelper: Error playing step counter sound: $e');
    }
  }

  /// Play play button sound (for timer start)
  Future<void> playPlayButtonSound() async {
    if (!_soundsEnabled || !_isInitialized) return;
    try {
      await _playButtonPlayer?.seek(Duration.zero);
      await _playButtonPlayer?.play();
    } catch (e) {
      print('SoundHelper: Error playing play button sound: $e');
    }
  }

  /// Play stop button sound (for timer stop)
  Future<void> playStopButtonSound() async {
    if (!_soundsEnabled || !_isInitialized) return;
    try {
      await _stopButtonPlayer?.seek(Duration.zero);
      await _stopButtonPlayer?.play();
    } catch (e) {
      print('SoundHelper: Error playing stop button sound: $e');
    }
  }

  /// Dispose all audio players
  void dispose() {
    _completionPlayer?.dispose();
    _stepCounterPlayer?.dispose();
    _playButtonPlayer?.dispose();
    _stopButtonPlayer?.dispose();
    _isInitialized = false;
  }
}

