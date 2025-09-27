import 'package:http/http.dart' as http;
import 'dart:convert';

class FastApiService {
  static const String baseUrl = 'http://localhost:8000';

  /// Sends a message to the FastAPI backend and returns the response
  static Future<String> sendMessage(String message, [List<Map<String, String>>? conversationHistory]) async {
    try {
      final url = Uri.parse('$baseUrl/api/chat/send');

      // Prepare the request body
      Map<String, dynamic> requestBody = {
        'message': message,
      };

      // Add conversation history if provided
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        requestBody['conversation_history'] = conversationHistory;
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return responseData['response'] ?? 'No response received';
      } else {
        return 'Error: ${response.statusCode} - ${response.body}';
      }
    } catch (e) {
      return 'Error connecting to backend: $e';
    }
  }
}