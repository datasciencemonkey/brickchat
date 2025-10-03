import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for stream results setting
final streamResultsProvider = StateNotifierProvider<StreamResultsNotifier, bool>((ref) {
  return StreamResultsNotifier(ref);
});

/// Provider for TTS provider selection
final ttsProviderProvider = StateNotifierProvider<TtsProviderNotifier, String>((ref) {
  return TtsProviderNotifier();
});

/// Provider for TTS voice selection
final ttsVoiceProvider = StateNotifierProvider<TtsVoiceNotifier, String>((ref) {
  return TtsVoiceNotifier();
});

/// Provider for eager mode (auto-play TTS)
final eagerModeProvider = StateNotifierProvider<EagerModeNotifier, bool>((ref) {
  return EagerModeNotifier(ref);
});

/// Settings keys
class SettingsKeys {
  static const String streamResults = 'stream_results';
  static const String ttsProvider = 'tts_provider';
  static const String ttsVoice = 'tts_voice';
  static const String eagerMode = 'eager_mode';
}

/// Available TTS providers
enum TtsProvider {
  replicate('Replicate (Kokoro-82M)'),
  deepgram('Deepgram (Aura)');

  final String displayName;
  const TtsProvider(this.displayName);

  String get value => name;
}

/// Available Replicate voices for Kokoro-82M
class ReplicateVoices {
  static const List<String> voices = [
    'af_alloy',
    'af_aoede',
    'af_bella',
    'af_jessica',
    'af_kore',
    'af_nicole',
    'af_nova',
    'af_river',
    'af_sarah',
    'af_sky',
    'am_adam',
    'am_echo',
    'am_eric',
    'am_fenrir',
    'am_liam',
    'am_michael',
    'am_onyx',
    'am_puck',
  ];

  static String getDisplayName(String voice) {
    // Convert voice code to display name (e.g., 'af_nicole' -> 'Nicole (Female)')
    final parts = voice.split('_');
    if (parts.length != 2) return voice;

    final gender = parts[0] == 'af' ? 'Female' : 'Male';
    final name = parts[1][0].toUpperCase() + parts[1].substring(1);
    return '$name ($gender)';
  }
}

/// Available Deepgram voices
class DeepgramVoices {
  static const List<String> voices = [
    'aura-2-thalia-en',
    'aura-2-asteria-en',
    'aura-2-luna-en',
    'aura-2-stella-en',
    'aura-2-athena-en',
    'aura-2-hera-en',
    'aura-2-orion-en',
    'aura-2-arcas-en',
    'aura-2-perseus-en',
    'aura-2-angus-en',
    'aura-2-orpheus-en',
    'aura-2-helios-en',
    'aura-2-zeus-en',
  ];

  static String getDisplayName(String voice) {
    // Extract name from voice ID (e.g., 'aura-2-thalia-en' -> 'Thalia')
    final parts = voice.split('-');
    if (parts.length >= 3) {
      final name = parts[2];
      return name[0].toUpperCase() + name.substring(1);
    }
    return voice;
  }
}

/// Stream results setting notifier
class StreamResultsNotifier extends StateNotifier<bool> {
  final Ref _ref;

  StreamResultsNotifier(this._ref) : super(false) {
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

  /// Set the stream results setting - automatically disables eager mode if enabling streaming
  Future<void> setStreamResults(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SettingsKeys.streamResults, enabled);
      state = enabled;

      // If enabling streaming, disable eager mode and notify the provider
      if (enabled) {
        await prefs.setBool(SettingsKeys.eagerMode, false);
        // Force the eager mode provider to update its state
        _ref.read(eagerModeProvider.notifier).state = false;
      }
    } catch (e) {
      // If saving fails, revert to previous state
      // The state doesn't change, so UI remains consistent
    }
  }
}

/// TTS provider setting notifier
class TtsProviderNotifier extends StateNotifier<String> {
  TtsProviderNotifier() : super(TtsProvider.replicate.value) {
    _loadSetting();
  }

  /// Load the TTS provider setting from SharedPreferences
  Future<void> _loadSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString(SettingsKeys.ttsProvider) ?? TtsProvider.replicate.value;
      state = provider;
    } catch (e) {
      state = TtsProvider.replicate.value;
    }
  }

  /// Set the TTS provider
  Future<void> setProvider(String provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SettingsKeys.ttsProvider, provider);
      state = provider;
    } catch (e) {
      // If saving fails, state doesn't change
    }
  }
}

/// TTS voice setting notifier
class TtsVoiceNotifier extends StateNotifier<String> {
  TtsVoiceNotifier() : super('af_nicole') {
    _loadSetting();
  }

  /// Load the TTS voice setting from SharedPreferences
  Future<void> _loadSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voice = prefs.getString(SettingsKeys.ttsVoice) ?? 'af_nicole';
      state = voice;
    } catch (e) {
      state = 'af_nicole';
    }
  }

  /// Set the TTS voice
  Future<void> setVoice(String voice) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SettingsKeys.ttsVoice, voice);
      state = voice;
    } catch (e) {
      // If saving fails, state doesn't change
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

/// Eager mode setting notifier
class EagerModeNotifier extends StateNotifier<bool> {
  final Ref _ref;

  EagerModeNotifier(this._ref) : super(false) {
    _loadSetting();
  }

  /// Load the eager mode setting from SharedPreferences
  Future<void> _loadSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final eagerMode = prefs.getBool(SettingsKeys.eagerMode) ?? false;
      state = eagerMode;
    } catch (e) {
      state = false;
    }
  }

  /// Toggle eager mode
  Future<void> toggleEagerMode() async {
    await setEagerMode(!state);
  }

  /// Set eager mode - automatically disables streaming if enabling eager mode
  Future<void> setEagerMode(bool enabled) async {
    try {
      // If enabling eager mode, ensure streaming is disabled
      if (enabled) {
        final streamEnabled = _ref.read(streamResultsProvider);
        if (streamEnabled) {
          // Disable streaming in SharedPreferences and update the provider state
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(SettingsKeys.streamResults, false);
          _ref.read(streamResultsProvider.notifier).state = false;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SettingsKeys.eagerMode, enabled);
      state = enabled;
    } catch (e) {
      // If saving fails, state doesn't change
    }
  }
}

/// Extension for easy access to TTS settings
extension TtsSettingsRef on WidgetRef {
  /// Get the current TTS provider
  String get ttsProvider => watch(ttsProviderProvider);

  /// Get the TTS provider notifier
  TtsProviderNotifier get ttsProviderNotifier => read(ttsProviderProvider.notifier);

  /// Get the current TTS voice
  String get ttsVoice => watch(ttsVoiceProvider);

  /// Get the TTS voice notifier
  TtsVoiceNotifier get ttsVoiceNotifier => read(ttsVoiceProvider.notifier);

  /// Get the current eager mode setting
  bool get eagerMode => watch(eagerModeProvider);

  /// Get the eager mode notifier
  EagerModeNotifier get eagerModeNotifier => read(eagerModeProvider.notifier);
}