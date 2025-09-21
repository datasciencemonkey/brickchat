import 'package:uuid/uuid.dart';

class AppUser {
  const AppUser({
    required this.id,
    this.firstName,
    this.lastName,
    this.imageUrl,
    this.metadata,
    this.status = UserStatus.offline,
    this.lastSeen,
    this.createdAt,
  });

  final String id;
  final String? firstName;
  final String? lastName;
  final String? imageUrl;
  final Map<String, dynamic>? metadata;
  final UserStatus status;
  final DateTime? lastSeen;
  final DateTime? createdAt;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      imageUrl: json['imageUrl'] as String?,
      status: UserStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => UserStatus.offline,
      ),
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'] as String)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'imageUrl': imageUrl,
      'status': status.name,
      'lastSeen': lastSeen?.toIso8601String(),
      'metadata': metadata,
    };
  }

  AppUser copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? imageUrl,
    UserStatus? status,
    DateTime? lastSeen,
    Map<String, dynamic>? metadata,
  }) {
    return AppUser(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      imageUrl: imageUrl ?? this.imageUrl,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      metadata: metadata ?? this.metadata,
    );
  }

  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (firstName != null) {
      return firstName!;
    } else if (lastName != null) {
      return lastName!;
    } else {
      return 'User';
    }
  }

  String get initials {
    final first = firstName?.isNotEmpty == true ? firstName![0] : '';
    final last = lastName?.isNotEmpty == true ? lastName![0] : '';
    if (first.isNotEmpty && last.isNotEmpty) {
      return '$first$last'.toUpperCase();
    } else if (first.isNotEmpty) {
      return first.toUpperCase();
    } else if (last.isNotEmpty) {
      return last.toUpperCase();
    } else {
      return 'U';
    }
  }

  static AppUser generateMockUser({
    String? id,
    String? firstName,
    String? lastName,
    UserStatus status = UserStatus.online,
  }) {
    return AppUser(
      id: id ?? const Uuid().v4(),
      firstName: firstName ?? 'John',
      lastName: lastName ?? 'Doe',
      status: status,
      lastSeen: status == UserStatus.offline
          ? DateTime.now().subtract(const Duration(minutes: 5))
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUser &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

enum UserStatus {
  online,
  away,
  offline,
}

extension UserStatusExtension on UserStatus {
  String get displayName {
    switch (this) {
      case UserStatus.online:
        return 'Online';
      case UserStatus.away:
        return 'Away';
      case UserStatus.offline:
        return 'Offline';
    }
  }

  bool get isOnline => this == UserStatus.online;
  bool get isAway => this == UserStatus.away;
  bool get isOffline => this == UserStatus.offline;
}