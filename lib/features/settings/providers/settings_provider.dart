import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for stream results setting
final streamResultsProvider = StateNotifierProvider<StreamResultsNotifier, bool>((ref) {
  return StreamResultsNotifier();
});

/// Settings keys
class SettingsKeys {
  static const String streamResults = 'stream_results';
}

/// Stream results setting notifier
class StreamResultsNotifier extends StateNotifier<bool> {
  StreamResultsNotifier() : super(false) {
    _loadSetting();
  }

  /// Load the stream results setting from SharedPreferences
  Future<void> _loadSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final streamResults = prefs.getBool(SettingsKeys.streamResults) ?? false;
      state = streamResults;
    } catch (e) {
      // If there's an error loading, default to false (non-streaming)
      state = false;
    }
  }

  /// Toggle the stream results setting
  Future<void> toggleStreamResults() async {
    await setStreamResults(!state);
  }

  /// Set the stream results setting
  Future<void> setStreamResults(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SettingsKeys.streamResults, enabled);
      state = enabled;
    } catch (e) {
      // If saving fails, revert to previous state
      // The state doesn't change, so UI remains consistent
    }
  }
}

/// Extension for easy access to stream results setting
extension StreamResultsRef on WidgetRef {
  /// Get the current stream results setting
  bool get streamResults => watch(streamResultsProvider);

  /// Get the stream results notifier
  StreamResultsNotifier get streamResultsNotifier => read(streamResultsProvider.notifier);
}