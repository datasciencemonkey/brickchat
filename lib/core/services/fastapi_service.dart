import 'package:http/http.dart' as http;
import 'dart:convert';

class FastApiService {
  static const String baseUrl = 'http://localhost:8000';

  /// Sends a message to the FastAPI backend and returns complete response (DEFAULT)
  /// Uses non-streaming mode (stream=false) for faster, complete responses
  static Future<Map<String, dynamic>> sendMessage(String message, {
    List<Map<String, String>>? conversationHistory,
    String? threadId,
    String userId = "dev_user",
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/chat/send');

      // Prepare the request body with stream=false
      Map<String, dynamic> requestBody = {
        'message': message,
        'stream': false, // Default to non-streaming mode
        'user_id': userId,
      };

      // Add thread ID if provided
      if (threadId != null) {
        requestBody['thread_id'] = threadId;
      }

      // Add conversation history if provided
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        requestBody['conversation_history'] = conversationHistory;
      }

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          return {
            'response': data['response'] ?? '',
            'thread_id': data['thread_id'],
            'user_message_id': data['user_message_id'],
            'assistant_message_id': data['assistant_message_id'],
          };
        } else {
          return {
            'error': 'Error: ${data['response'] ?? 'Unknown error'}',
          };
        }
      } else {
        return {
          'error': 'Error: ${response.statusCode} - ${response.body}',
        };
      }
    } catch (e) {
      return {
        'error': 'Error connecting to backend: $e',
      };
    }
  }

  /// Sends a message to the FastAPI backend and returns streaming response
  /// Uses streaming mode (stream=true) for real-time token-by-token responses
  /// Returns a stream of maps containing either 'content', 'footnotes', or 'metadata'
  static Stream<Map<String, dynamic>> sendMessageStream(String message, {
    List<Map<String, String>>? conversationHistory,
    String? threadId,
    String userId = "dev_user",
  }) async* {
    try {
      final url = Uri.parse('$baseUrl/api/chat/send');

      // Prepare the request body with stream=true
      Map<String, dynamic> requestBody = {
        'message': message,
        'stream': true, // Explicitly enable streaming mode
        'user_id': userId,
      };

      // Add thread ID if provided
      if (threadId != null) {
        requestBody['thread_id'] = threadId;
      }

      // Add conversation history if provided
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        requestBody['conversation_history'] = conversationHistory;
      }

      final request = http.Request('POST', url);
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode(requestBody);

      final streamedResponse = await request.send();

      if (streamedResponse.statusCode == 200) {
        await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
          // Parse each chunk for data: lines
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.startsWith('data: ')) {
              try {
                final jsonStr = line.substring(6); // Remove 'data: '
                final data = json.decode(jsonStr);

                if (data['error'] != null) {
                  yield {'error': data['error']};
                  return;
                } else if (data['done'] == true) {
                  return;
                } else if (data['content'] != null) {
                  yield {'content': data['content']};
                } else if (data['footnotes'] != null) {
                  yield {'footnotes': data['footnotes']};
                }
              } catch (e) {
                // Skip malformed chunks
                continue;
              }
            }
          }
        }
      } else {
        yield {'error': 'Error: ${streamedResponse.statusCode}'};
      }
    } catch (e) {
      yield {'error': 'Error connecting to backend: $e'};
    }
  }

  /// Legacy wrapper that uses the new non-streaming method
  @Deprecated('Use sendMessage() instead for non-streaming or sendMessageStream() for streaming')
  static Future<String> sendMessageLegacy(String message, [List<Map<String, String>>? conversationHistory]) async {
    final response = await sendMessage(
      message,
      conversationHistory: conversationHistory,
    );
    return response['response'] ?? response['error'] ?? 'Unknown error';
  }

  /// Get text-to-speech audio URL from backend
  static String getTtsAudioUrl(String text) {
    // Return the URL that will be used to fetch the audio
    return '$baseUrl/api/tts/speak';
  }

  /// Request text-to-speech audio from backend
  static Future<http.Response> requestTts(String text, {String? provider, String? voice}) async {
    try {
      final url = Uri.parse('$baseUrl/api/tts/speak');
      final requestBody = {
        'text': text,
        if (provider != null) 'provider': provider,
        if (voice != null) 'voice': voice,
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );
      return response;
    } catch (e) {
      throw Exception('Error requesting TTS: $e');
    }
  }

  /// Update feedback (like/dislike) for a message
  static Future<Map<String, dynamic>> updateFeedback({
    required String messageId,
    required String threadId,
    required String feedbackType, // 'like', 'dislike', or 'none'
    String userId = "dev_user",
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/feedback/feedback');

      Map<String, dynamic> requestBody = {
        'message_id': messageId,
        'thread_id': threadId,
        'user_id': userId,
        'feedback_type': feedbackType,
      };

      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'error': 'Error: ${response.statusCode} - ${response.body}',
        };
      }
    } catch (e) {
      return {
        'error': 'Error updating feedback: $e',
      };
    }
  }
}