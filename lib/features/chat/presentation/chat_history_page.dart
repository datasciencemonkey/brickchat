import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/services/fastapi_service.dart';

class ChatHistoryPage extends ConsumerStatefulWidget {
  /// Callback when a thread is selected.
  /// Parameters: threadId, messages list, documents list (for chip reconstruction)
  final Function(String threadId, List<Map<String, dynamic>> messages, List<Map<String, dynamic>> documents)? onThreadSelected;
  final String userId;

  const ChatHistoryPage({
    super.key,
    this.onThreadSelected,
    this.userId = "dev_user",
  });

  @override
  ConsumerState<ChatHistoryPage> createState() => _ChatHistoryPageState();
}

class _ChatHistoryPageState extends ConsumerState<ChatHistoryPage> {
  List<Map<String, dynamic>> _threads = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadThreads() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final threads = await FastApiService.getUserThreads(widget.userId);
      if (mounted) {
        setState(() {
          _threads = threads;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load chat history: $e'),
            backgroundColor: Colors.red.withValues(alpha: 0.85),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredThreads {
    if (_searchQuery.isEmpty) {
      return _threads;
    }
    return _threads.where((thread) {
      final firstMessage = thread['first_user_message']?.toString().toLowerCase() ?? '';
      final lastMessage = thread['last_message']?.toString().toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return firstMessage.contains(query) || lastMessage.contains(query);
    }).toList();
  }

  String _formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return 'Unknown time';

    DateTime dateTime;
    try {
      if (timestamp is String) {
        dateTime = DateTime.parse(timestamp);
      } else {
        return 'Unknown time';
      }
    } catch (e) {
      return 'Unknown time';
    }

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${(difference.inDays / 7).floor()} weeks ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  String _getTruncatedTitle(String? message) {
    if (message == null || message.isEmpty) {
      return 'New conversation';
    }
    // Remove markdown and clean up text
    String cleaned = message
        .replaceAll(RegExp(r'\*\*'), '') // Remove bold markdown
        .replaceAll(RegExp(r'\n+'), ' ') // Replace newlines with spaces
        .trim();

    // Truncate to reasonable length for title
    if (cleaned.length > 80) {
      return '${cleaned.substring(0, 80)}...';
    }
    return cleaned;
  }

  Future<void> _selectThread(String threadId) async {
    // Fetch messages and documents for this thread (single API call)
    final response = await FastApiService.getThreadMessages(threadId);
    final messages = response['messages'] as List<Map<String, dynamic>>;
    final documents = response['documents'] as List<Map<String, dynamic>>;

    if (widget.onThreadSelected != null) {
      widget.onThreadSelected!(threadId, messages, documents);
    }

    // Close the history page
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final isDark = ref.isDarkMode;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? appColors.popover : appColors.sidebar,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? appColors.sidebarForeground : appColors.sidebarForeground),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Your chat history',
          style: TextStyle(
            color: isDark ? appColors.sidebarForeground : appColors.sidebarForeground,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: isDark ? appColors.sidebarForeground : appColors.sidebarForeground),
            onPressed: () {
              // Close history and start new thread
              Navigator.of(context).pop();
              if (widget.onThreadSelected != null) {
                widget.onThreadSelected!(null.toString(), [], []);
              }
            },
            tooltip: 'New conversation',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? appColors.popover : appColors.sidebar,
              border: Border(
                bottom: BorderSide(
                  color: appColors.sidebarBorder.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  style: TextStyle(
                    color: isDark ? appColors.sidebarForeground : appColors.sidebarForeground,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search your chats...',
                    hintStyle: TextStyle(
                      color: appColors.mutedForeground,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: appColors.mutedForeground,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? appColors.muted.withValues(alpha: 0.2)
                        : appColors.muted.withValues(alpha: 0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_filteredThreads.length} chat${_filteredThreads.length != 1 ? 's' : ''}',
                  style: TextStyle(
                    color: appColors.mutedForeground,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          // Threads list
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: appColors.accent,
                    ),
                  )
                : _filteredThreads.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: appColors.mutedForeground.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No chat history yet'
                                  : 'No chats match your search',
                              style: TextStyle(
                                color: appColors.mutedForeground,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Start a new conversation to see it here'
                                  : 'Try a different search term',
                              style: TextStyle(
                                color: appColors.mutedForeground.withValues(alpha: 0.7),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _filteredThreads.length,
                        itemBuilder: (context, index) {
                          final thread = _filteredThreads[index];
                          final title = _getTruncatedTitle(
                            thread['first_user_message']?.toString()
                          );
                          final lastMessageTime = _formatTimeAgo(
                            thread['last_message_time']
                          );
                          final agentEndpoint = thread['agent_endpoint']?.toString() ?? 'Unknown';

                          return InkWell(
                            onTap: () => _selectThread(thread['thread_id']),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: appColors.sidebarBorder.withValues(alpha: 0.1),
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      color: isDark ? appColors.sidebarForeground : appColors.sidebarForeground,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Last message $lastMessageTime',
                                          style: TextStyle(
                                            color: appColors.mutedForeground,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      // Agent endpoint badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? appColors.muted.withValues(alpha: 0.3)
                                              : appColors.muted.withValues(alpha: 0.5),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: appColors.sidebarBorder.withValues(alpha: 0.2),
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.smart_toy_outlined,
                                              size: 11,
                                              color: appColors.mutedForeground.withValues(alpha: 0.7),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              agentEndpoint,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: appColors.mutedForeground.withValues(alpha: 0.8),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}