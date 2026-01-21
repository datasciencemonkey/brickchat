// lib/features/autonomous/services/autonomous_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../providers/autonomous_provider.dart';

/// Service for autonomous mode API calls
class AutonomousService {
  static String get baseUrl {
    if (kIsWeb) {
      return ''; // Same origin in production
    }
    return 'http://localhost:8000';
  }

  /// Discover agents from Databricks (admin only)
  static Future<Map<String, dynamic>> discoverAgents() async {
    try {
      final url = Uri.parse('$baseUrl/api/agents/discover');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 403) {
        return {'error': 'Admin access required'};
      } else {
        return {'error': 'Discovery failed: ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': 'Connection error: $e'};
    }
  }

  /// Get all agents (admin view)
  static Future<List<AutonomousAgent>> getAllAgents() async {
    try {
      final url = Uri.parse('$baseUrl/api/agents/all');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((j) => AutonomousAgent.fromJson(j)).toList();
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to fetch agents: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get enabled agents only (for router/chat)
  static Future<List<AutonomousAgent>> getEnabledAgents() async {
    try {
      final url = Uri.parse('$baseUrl/api/agents');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((j) => AutonomousAgent.fromJson(j)).toList();
      } else {
        throw Exception('Failed to fetch enabled agents: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Update agent (admin only)
  static Future<AutonomousAgent?> updateAgent(
    String agentId, {
    String? name,
    String? description,
    Map<String, dynamic>? adminMetadata,
    String? routerMetadata,
    String? status,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/agents/$agentId');

      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (description != null) body['description'] = description;
      if (adminMetadata != null) body['admin_metadata'] = adminMetadata;
      if (routerMetadata != null) body['router_metadata'] = routerMetadata;
      if (status != null) body['status'] = status;

      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return AutonomousAgent.fromJson(json.decode(response.body));
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else if (response.statusCode == 404) {
        throw Exception('Agent not found');
      } else {
        throw Exception('Update failed: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Delete agent (admin only)
  static Future<bool> deleteAgent(String agentId) async {
    try {
      final url = Uri.parse('$baseUrl/api/agents/$agentId');
      final response = await http.delete(url);

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else if (response.statusCode == 404) {
        throw Exception('Agent not found');
      } else {
        throw Exception('Delete failed: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Send message in autonomous mode (streaming)
  static Stream<Map<String, dynamic>> sendAutonomousMessage(
    String message, {
    List<Map<String, String>>? conversationHistory,
    String? threadId,
  }) async* {
    try {
      final url = Uri.parse('$baseUrl/api/agents/chat/autonomous');

      final requestBody = <String, dynamic>{
        'message': message,
      };
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        requestBody['conversation_history'] = conversationHistory;
      }
      if (threadId != null) {
        requestBody['thread_id'] = threadId;
      }

      final request = http.Request('POST', url);
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode(requestBody);

      final streamedResponse = await request.send();

      if (streamedResponse.statusCode == 200) {
        await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.startsWith('data: ')) {
              try {
                final jsonStr = line.substring(6);
                final data = json.decode(jsonStr);

                if (data['error'] != null) {
                  yield {'error': data['error']};
                  return;
                } else if (data['done'] == true) {
                  yield {
                    'done': true,
                    'thread_id': data['thread_id'],
                    'assistant_message_id': data['assistant_message_id'],
                  };
                  return;
                } else if (data['routing'] != null) {
                  yield {'routing': data['routing']};
                } else if (data['content'] != null) {
                  yield {'content': data['content']};
                }
              } catch (e) {
                continue;
              }
            }
          }
        }
      } else if (streamedResponse.statusCode == 400) {
        yield {'error': 'No agents enabled for autonomous mode'};
      } else {
        yield {'error': 'Request failed: ${streamedResponse.statusCode}'};
      }
    } catch (e) {
      yield {'error': 'Connection error: $e'};
    }
  }
}
