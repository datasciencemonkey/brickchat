import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

class FastApiService {
  // Dynamic base URL that works in both development and production
  static String get baseUrl {
    if (kIsWeb) {
      // In web/production, use relative URLs (same origin as the app)
      // This works for both localhost development and Databricks Apps deployment
      return ''; // Empty string means same origin
    }
    // For non-web platforms (desktop), use localhost
    return 'http://localhost:8000';
  }

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
            'citations': data['citations'] ?? [],
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
                } else if (data['metadata'] != null) {
                  yield {'metadata': data['metadata']};
                } else if (data['content'] != null) {
                  yield {'content': data['content']};
                } else if (data['reasoning'] != null) {
                  yield {'reasoning': data['reasoning']};
                } else if (data['citations'] != null) {
                  yield {'citations': data['citations']};
                } else if (data['footnotes'] != null) {
                  // Legacy support for footnotes
                  yield {'footnotes': data['footnotes']};
                } else if (data['assistant_message_id'] != null) {
                  yield {'assistant_message_id': data['assistant_message_id']};
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
  ///
  /// Parameters:
  /// - text: The text to convert to speech
  /// - provider: TTS provider ('replicate' or 'deepgram')
  /// - voice: Voice ID for the selected provider
  /// - messageId: Message ID for caching (optional)
  /// - saveToVolume: Whether to cache audio to Databricks Volume (optional)
  static Future<http.Response> requestTts(
    String text, {
    String? provider,
    String? voice,
    String? messageId,
    bool? saveToVolume,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/tts/speak');
      final requestBody = {
        'text': text,
        if (provider != null) 'provider': provider,
        if (voice != null) 'voice': voice,
        if (messageId != null) 'message_id': messageId,
        if (saveToVolume != null) 'save_to_volume': saveToVolume,
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

  /// Stream TTS audio chunks via SSE (for eager mode)
  /// Returns a stream of events containing audio chunks or control messages
  ///
  /// Event types:
  /// - {'type': 'audio', 'chunk': List<int>} - Base64-decoded audio chunk
  /// - {'type': 'done', 'sentences': int} - Streaming complete
  /// - {'type': 'error', 'message': String} - Error occurred
  static Stream<Map<String, dynamic>> streamTts(
    String text, {
    String? voice,
  }) async* {
    try {
      final url = Uri.parse('$baseUrl/api/tts/speak-stream');

      final request = http.Request('POST', url);
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode({
        'text': text,
        if (voice != null) 'voice': voice,
      });

      final streamedResponse = await request.send();

      if (streamedResponse.statusCode == 200) {
        String buffer = '';

        await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
          buffer += chunk;

          // Process complete SSE messages (lines ending with \n\n)
          while (buffer.contains('\n\n')) {
            final endIndex = buffer.indexOf('\n\n');
            final message = buffer.substring(0, endIndex);
            buffer = buffer.substring(endIndex + 2);

            // Parse each line in the message
            for (final line in message.split('\n')) {
              if (line.startsWith('data: ')) {
                try {
                  final jsonStr = line.substring(6); // Remove 'data: '
                  final data = json.decode(jsonStr);

                  if (data['type'] == 'audio' && data['chunk'] != null) {
                    // Decode base64 audio chunk
                    final audioBytes = base64Decode(data['chunk']);
                    yield {'type': 'audio', 'chunk': audioBytes};
                  } else if (data['type'] == 'done') {
                    yield {
                      'type': 'done',
                      'sentences': data['sentences'] ?? 0,
                    };
                    return;
                  } else if (data['type'] == 'error') {
                    yield {
                      'type': 'error',
                      'message': data['message'] ?? 'Unknown error',
                    };
                    return;
                  }
                } catch (e) {
                  // Skip malformed chunks
                  continue;
                }
              }
            }
          }
        }
      } else {
        yield {
          'type': 'error',
          'message': 'Streaming TTS failed: ${streamedResponse.statusCode}',
        };
      }
    } catch (e) {
      yield {
        'type': 'error',
        'message': 'Error connecting to streaming TTS: $e',
      };
    }
  }

  /// Update feedback (like/dislike) for a message
  /// User identity now comes from auth context on the backend
  static Future<Map<String, dynamic>> updateFeedback({
    required String messageId,
    required String threadId,
    required String feedbackType, // 'like', 'dislike', or 'none'
    String? userId, // Deprecated: user_id now comes from auth headers
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/feedback/feedback');

      // user_id is no longer needed - comes from auth context
      Map<String, dynamic> requestBody = {
        'message_id': messageId,
        'thread_id': threadId,
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

  /// Fetch all threads for the current user (user identity comes from auth context on backend)
  static Future<List<Map<String, dynamic>>> getUserThreads([String? userId]) async {
    try {
      // User identity now comes from auth headers on the backend
      final url = Uri.parse('$baseUrl/api/chat/threads');

      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['threads'] ?? []);
      } else {
        print('Error fetching threads: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error fetching threads: $e');
      return [];
    }
  }

  /// Fetch all messages for a specific thread
  static Future<List<Map<String, dynamic>>> getThreadMessages(String threadId) async {
    try {
      final url = Uri.parse('$baseUrl/api/chat/threads/$threadId/messages');

      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['messages'] ?? []);
      } else {
        print('Error fetching thread messages: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error fetching thread messages: $e');
      return [];
    }
  }

  /// Get current chat configuration including agent endpoint
  static Future<Map<String, dynamic>> getChatConfig() async {
    try {
      final url = Uri.parse('$baseUrl/api/chat/config');

      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('Error fetching chat config: ${response.statusCode} - ${response.body}');
        return {'agent_endpoint': 'Unknown'};
      }
    } catch (e) {
      print('Error fetching chat config: $e');
      return {'agent_endpoint': 'Unknown'};
    }
  }
}