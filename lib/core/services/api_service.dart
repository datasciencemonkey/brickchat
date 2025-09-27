import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

enum ApiBackend {
  anthropic('Anthropic Claude', 'https://api.anthropic.com/v1'),
  openai('OpenAI GPT', 'https://api.openai.com/v1'),
  cohere('Cohere', 'https://api.cohere.ai/v1'),
  databricks('Databricks Endpoint', 'https://adb-<workspace-id>.<random-number>.azuredatabricks.net/serving-endpoints'),
  custom('Custom API', '');

  const ApiBackend(this.displayName, this.baseUrl);

  final String displayName;
  final String baseUrl;
}

class ApiSettings {
  final ApiBackend selectedBackend;
  final String? customApiUrl;
  final String? apiKey;
  final Map<String, String> headers;
  final int timeoutSeconds;

  const ApiSettings({
    this.selectedBackend = ApiBackend.anthropic,
    this.customApiUrl,
    this.apiKey,
    this.headers = const {},
    this.timeoutSeconds = 120,
  });

  ApiSettings copyWith({
    ApiBackend? selectedBackend,
    String? customApiUrl,
    String? apiKey,
    Map<String, String>? headers,
    int? timeoutSeconds,
  }) {
    return ApiSettings(
      selectedBackend: selectedBackend ?? this.selectedBackend,
      customApiUrl: customApiUrl ?? this.customApiUrl,
      apiKey: apiKey ?? this.apiKey,
      headers: headers ?? this.headers,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  String get effectiveBaseUrl {
    if (selectedBackend == ApiBackend.custom && customApiUrl != null) {
      return customApiUrl!;
    }
    return selectedBackend.baseUrl;
  }
}

class ApiService extends StateNotifier<ApiSettings> {
  ApiService() : super(const ApiSettings()) {
    _loadSettings();
  }

  static const String _selectedBackendKey = 'api_selected_backend';
  static const String _customApiUrlKey = 'api_custom_url';
  static const String _apiKeyKey = 'api_key';
  static const String _timeoutSecondsKey = 'api_timeout_seconds';

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final backendIndex = prefs.getInt(_selectedBackendKey);
      final customApiUrl = prefs.getString(_customApiUrlKey);
      final apiKey = prefs.getString(_apiKeyKey);
      final timeoutSeconds = prefs.getInt(_timeoutSecondsKey) ?? 120;

      ApiBackend selectedBackend = ApiBackend.anthropic;
      if (backendIndex != null && backendIndex < ApiBackend.values.length) {
        selectedBackend = ApiBackend.values[backendIndex];
      }

      state = ApiSettings(
        selectedBackend: selectedBackend,
        customApiUrl: customApiUrl,
        apiKey: apiKey,
        timeoutSeconds: timeoutSeconds,
      );
    } catch (e) {
      // Handle error silently, keep default settings
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_selectedBackendKey, state.selectedBackend.index);

      if (state.customApiUrl != null) {
        await prefs.setString(_customApiUrlKey, state.customApiUrl!);
      } else {
        await prefs.remove(_customApiUrlKey);
      }

      if (state.apiKey != null) {
        await prefs.setString(_apiKeyKey, state.apiKey!);
      } else {
        await prefs.remove(_apiKeyKey);
      }

      await prefs.setInt(_timeoutSecondsKey, state.timeoutSeconds);
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> setBackend(ApiBackend backend) async {
    state = state.copyWith(selectedBackend: backend);
    await _saveSettings();
  }

  Future<void> setCustomApiUrl(String url) async {
    state = state.copyWith(customApiUrl: url);
    await _saveSettings();
  }

  Future<void> setApiKey(String key) async {
    state = state.copyWith(apiKey: key);
    await _saveSettings();
  }

  Future<void> setTimeout(int seconds) async {
    state = state.copyWith(timeoutSeconds: seconds);
    await _saveSettings();
  }

  // HTTP client methods that use the configured backend
  Future<Map<String, dynamic>> sendMessage(String message) async {
    final url = '${state.effectiveBaseUrl}/chat/completions';

    // This is a placeholder implementation
    // In a real app, you'd implement actual HTTP requests here
    switch (state.selectedBackend) {
      case ApiBackend.anthropic:
        return await _sendAnthropicMessage(url, message);
      case ApiBackend.openai:
        return await _sendOpenAIMessage(url, message);
      case ApiBackend.cohere:
        return await _sendCohereMessage(url, message);
      case ApiBackend.databricks:
        return await _sendDatabricksMessage(url, message);
      case ApiBackend.custom:
        return await _sendCustomMessage(url, message);
    }
  }

  Future<Map<String, dynamic>> _sendAnthropicMessage(String url, String message) async {
    // Placeholder for Anthropic API implementation
    await Future.delayed(const Duration(milliseconds: 500));
    return {
      'response': 'Response from Anthropic Claude API: $message',
      'backend': 'anthropic',
    };
  }

  Future<Map<String, dynamic>> _sendOpenAIMessage(String url, String message) async {
    // Placeholder for OpenAI API implementation
    await Future.delayed(const Duration(milliseconds: 500));
    return {
      'response': 'Response from OpenAI GPT API: $message',
      'backend': 'openai',
    };
  }

  Future<Map<String, dynamic>> _sendCohereMessage(String url, String message) async {
    // Placeholder for Cohere API implementation
    await Future.delayed(const Duration(milliseconds: 500));
    return {
      'response': 'Response from Cohere API: $message',
      'backend': 'cohere',
    };
  }

  Future<Map<String, dynamic>> _sendDatabricksMessage(String url, String message) async {
    try {
      // For local development, assume FastAPI is running on localhost:8000
      const fastApiUrl = 'http://localhost:8000/api/chat/send';

      final response = await http.post(
        Uri.parse(fastApiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'message': message,
        }),
      ).timeout(Duration(seconds: state.timeoutSeconds));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return {
          'response': responseData['response'] ?? 'No response received',
          'backend': 'databricks',
        };
      } else {
        return {
          'response': 'Error: ${response.statusCode} - ${response.body}',
          'backend': 'databricks',
        };
      }
    } catch (e) {
      return {
        'response': 'Error connecting to Databricks endpoint: $e',
        'backend': 'databricks',
      };
    }
  }

  Future<Map<String, dynamic>> _sendCustomMessage(String url, String message) async {
    // Placeholder for custom API implementation
    await Future.delayed(const Duration(milliseconds: 500));
    return {
      'response': 'Response from custom API: $message',
      'backend': 'custom',
    };
  }

  bool get isConfigured {
    if (state.selectedBackend == ApiBackend.databricks) {
      return state.customApiUrl?.isNotEmpty == true;
    }
    if (state.selectedBackend == ApiBackend.custom) {
      return state.customApiUrl?.isNotEmpty == true && state.apiKey?.isNotEmpty == true;
    }
    return state.apiKey?.isNotEmpty == true;
  }
}

final apiServiceProvider = StateNotifierProvider<ApiService, ApiSettings>((ref) {
  return ApiService();
});

extension ApiContext on WidgetRef {
  ApiService get apiService => read(apiServiceProvider.notifier);
  ApiSettings get apiSettings => watch(apiServiceProvider);
  bool get isApiConfigured => watch(apiServiceProvider.select((settings) =>
    settings.selectedBackend == ApiBackend.custom
      ? settings.customApiUrl?.isNotEmpty == true && settings.apiKey?.isNotEmpty == true
      : settings.apiKey?.isNotEmpty == true));
}