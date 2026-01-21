// lib/features/autonomous/providers/autonomous_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys for autonomous mode settings persistence
class AutonomousSettingsKeys {
  static const String autonomousModeEnabled = 'autonomous_mode_enabled';
  static const String lastSelectedAgentId = 'last_selected_agent_id';
}

/// Represents an Agent Brick from the backend
class AutonomousAgent {
  final String agentId;
  final String endpointUrl;
  final String name;
  final String? description;
  final Map<String, dynamic> databricksMetadata;
  final Map<String, dynamic> adminMetadata;
  final String? routerMetadata; // Admin-provided context for intelligent routing
  final String status; // 'enabled', 'disabled', 'new'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AutonomousAgent({
    required this.agentId,
    required this.endpointUrl,
    required this.name,
    this.description,
    this.databricksMetadata = const {},
    this.adminMetadata = const {},
    this.routerMetadata,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory AutonomousAgent.fromJson(Map<String, dynamic> json) {
    return AutonomousAgent(
      agentId: json['agent_id'] ?? '',
      endpointUrl: json['endpoint_url'] ?? '',
      name: json['name'] ?? 'Unknown Agent',
      description: json['description'],
      databricksMetadata: json['databricks_metadata'] ?? {},
      adminMetadata: json['admin_metadata'] ?? {},
      routerMetadata: json['router_metadata'],
      status: json['status'] ?? 'new',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'agent_id': agentId,
    'endpoint_url': endpointUrl,
    'name': name,
    'description': description,
    'databricks_metadata': databricksMetadata,
    'admin_metadata': adminMetadata,
    'router_metadata': routerMetadata,
    'status': status,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  AutonomousAgent copyWith({
    String? agentId,
    String? endpointUrl,
    String? name,
    String? description,
    Map<String, dynamic>? databricksMetadata,
    Map<String, dynamic>? adminMetadata,
    String? routerMetadata,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AutonomousAgent(
      agentId: agentId ?? this.agentId,
      endpointUrl: endpointUrl ?? this.endpointUrl,
      name: name ?? this.name,
      description: description ?? this.description,
      databricksMetadata: databricksMetadata ?? this.databricksMetadata,
      adminMetadata: adminMetadata ?? this.adminMetadata,
      routerMetadata: routerMetadata ?? this.routerMetadata,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isEnabled => status == 'enabled';
  bool get isDisabled => status == 'disabled';
  bool get isNew => status == 'new';
  bool get hasRouterMetadata => routerMetadata != null && routerMetadata!.isNotEmpty;
}

/// Routing info attached to autonomous responses
class RoutingInfo {
  final AutonomousAgent agent;
  final String reason;

  RoutingInfo({required this.agent, required this.reason});

  factory RoutingInfo.fromJson(Map<String, dynamic> json) {
    return RoutingInfo(
      agent: AutonomousAgent.fromJson(json['agent'] ?? {}),
      reason: json['reason'] ?? 'No reason provided',
    );
  }
}

/// Provider for autonomous mode toggle state
final autonomousModeProvider = StateNotifierProvider<AutonomousModeNotifier, bool>((ref) {
  return AutonomousModeNotifier();
});

class AutonomousModeNotifier extends StateNotifier<bool> {
  AutonomousModeNotifier() : super(false) {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(AutonomousSettingsKeys.autonomousModeEnabled) ?? false;
      state = enabled;
    } catch (e) {
      state = false;
    }
  }

  Future<void> setAutonomousMode(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AutonomousSettingsKeys.autonomousModeEnabled, enabled);
      state = enabled;
    } catch (e) {
      // If save fails, don't update state
    }
  }

  void toggle() {
    setAutonomousMode(!state);
  }
}

/// Provider for the list of all agents (admin view)
final allAgentsProvider = StateNotifierProvider<AllAgentsNotifier, List<AutonomousAgent>>((ref) {
  return AllAgentsNotifier();
});

class AllAgentsNotifier extends StateNotifier<List<AutonomousAgent>> {
  AllAgentsNotifier() : super([]);

  void setAgents(List<AutonomousAgent> agents) {
    state = agents;
  }

  void updateAgent(AutonomousAgent updated) {
    state = state.map((a) => a.agentId == updated.agentId ? updated : a).toList();
  }

  void removeAgent(String agentId) {
    state = state.where((a) => a.agentId != agentId).toList();
  }

  void addAgent(AutonomousAgent agent) {
    if (!state.any((a) => a.agentId == agent.agentId)) {
      state = [...state, agent];
    }
  }
}

/// Provider for enabled agents only (for chat use)
final enabledAgentsProvider = Provider<List<AutonomousAgent>>((ref) {
  final allAgents = ref.watch(allAgentsProvider);
  return allAgents.where((a) => a.isEnabled).toList();
});

/// Provider to check if autonomous mode is available (at least one agent enabled)
final autonomousModeAvailableProvider = Provider<bool>((ref) {
  final enabledAgents = ref.watch(enabledAgentsProvider);
  return enabledAgents.isNotEmpty;
});

// ============ Search & Filter Providers ============

/// Provider for agent search query
final agentSearchQueryProvider = StateProvider<String>((ref) => '');

/// Provider for "show enabled only" filter toggle
final agentShowEnabledOnlyProvider = StateProvider<bool>((ref) => false);

/// Provider for filtered agents based on search query and enabled filter
final filteredAgentsProvider = Provider<List<AutonomousAgent>>((ref) {
  final allAgents = ref.watch(allAgentsProvider);
  final query = ref.watch(agentSearchQueryProvider).toLowerCase();
  final showEnabledOnly = ref.watch(agentShowEnabledOnlyProvider);

  return allAgents.where((agent) {
    // Filter by enabled status if toggle is on
    if (showEnabledOnly && !agent.isEnabled) return false;

    // Filter by search query
    if (query.isEmpty) return true;
    return agent.name.toLowerCase().contains(query) ||
        (agent.description?.toLowerCase().contains(query) ?? false) ||
        agent.endpointUrl.toLowerCase().contains(query) ||
        (agent.routerMetadata?.toLowerCase().contains(query) ?? false);
  }).toList();
});

/// Extension methods for easy access
extension AutonomousModeRef on WidgetRef {
  bool get isAutonomousMode => watch(autonomousModeProvider);
  AutonomousModeNotifier get autonomousModeNotifier => read(autonomousModeProvider.notifier);

  List<AutonomousAgent> get allAgents => watch(allAgentsProvider);
  AllAgentsNotifier get allAgentsNotifier => read(allAgentsProvider.notifier);

  List<AutonomousAgent> get enabledAgents => watch(enabledAgentsProvider);
  bool get isAutonomousModeAvailable => watch(autonomousModeAvailableProvider);

  // Search & filter extensions
  List<AutonomousAgent> get filteredAgents => watch(filteredAgentsProvider);
  String get agentSearchQuery => watch(agentSearchQueryProvider);
  bool get showEnabledAgentsOnly => watch(agentShowEnabledOnlyProvider);
}
