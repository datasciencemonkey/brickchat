import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidebarx/sidebarx.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/gradients.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/theme_toggle.dart';
import '../../../shared/widgets/speech_to_text_widget.dart';

class ChatHomePage extends ConsumerStatefulWidget {
  const ChatHomePage({super.key});

  @override
  ConsumerState<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends ConsumerState<ChatHomePage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showSpeechToText = false;

  // SidebarX controller
  late SidebarXController _sidebarController;

  @override
  void initState() {
    super.initState();
    _sidebarController = SidebarXController(selectedIndex: 0, extended: true);
    _loadInitialMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _sidebarController.dispose();
    super.dispose();
  }

  void _loadInitialMessages() {
    setState(() {
      _messages.addAll([
        ChatMessage(
          id: '1',
          text: 'Welcome to BrickChat! 🎉',
          isOwn: false,
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          author: 'Assistant',
        ),
        ChatMessage(
          id: '2',
          text: 'This demo showcases modern Flutter architecture with:',
          isOwn: false,
          timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
          author: 'Assistant',
        ),
        ChatMessage(
          id: '3',
          text: '• OKLCH Color System with Databricks branding\n• Responsive design with collapsible SidebarX\n• Dark mode with fancy gradients\n• Clean Architecture with Riverpod',
          isOwn: false,
          timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
          author: 'Assistant',
        ),
        ChatMessage(
          id: '4',
          text: 'Thanks for the demo! The gradient effects in dark mode look amazing.',
          isOwn: true,
          timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
          author: 'You',
        ),
        ChatMessage(
          id: '5',
          text: 'Feel free to toggle between light and dark themes to see the different styling approaches!',
          isOwn: false,
          timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
          author: 'Assistant',
        ),
      ]);
    });
  }

  void _sendMessage({String? text}) {
    final messageText = text ?? _messageController.text.trim();
    if (messageText.isEmpty) return;

    final message = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: messageText,
      isOwn: true,
      timestamp: DateTime.now(),
      author: 'You',
    );

    setState(() {
      _messages.add(message);
      _messageController.clear();
      _showSpeechToText = false; // Hide speech widget after sending
    });

    _scrollToBottom();

    // Simulate a response after a delay
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        final responses = [
          'That\'s a great point!',
          'I understand what you mean.',
          'Thanks for sharing that!',
          'Interesting perspective!',
          'I agree with you on that.',
          'Let me think about that...',
          'That makes sense!',
          'Good question!',
        ];

        final response = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: responses[DateTime.now().second % responses.length],
          isOwn: false,
          timestamp: DateTime.now(),
          author: 'Assistant',
        );

        setState(() {
          _messages.add(response);
        });

        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SidebarX(
            controller: _sidebarController,
            theme: _buildSidebarTheme(context),
            extendedTheme: _buildExtendedSidebarTheme(context),
            headerBuilder: (context, extended) => _buildSidebarHeader(extended),
            items: _buildSidebarItems(),
            footerDivider: Divider(color: context.appColors.sidebarBorder, height: 1),
            headerDivider: Divider(color: context.appColors.sidebarBorder, height: 1),
          ),
          Expanded(
            child: Column(
              children: [
                AppBar(
                  title: const Text(AppConstants.appName),
                  centerTitle: false,
                  actions: [
                    const ThemeToggle(),
                    const SizedBox(width: AppConstants.spacingSm),
                  ],
                ),
                Expanded(child: _buildChatBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  SidebarXTheme _buildSidebarTheme(BuildContext context) {
    final appColors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SidebarXTheme(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: isDark ? AppGradients.darkSidebarGradient : null,
        color: isDark ? null : appColors.sidebar,
        borderRadius: BorderRadius.circular(20),
      ),
      hoverColor: appColors.sidebarAccent,
      textStyle: TextStyle(
        color: appColors.sidebarForeground.withValues(alpha: 0.7),
        fontSize: 13,
      ),
      selectedTextStyle: TextStyle(
        color: appColors.sidebarPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      hoverTextStyle: TextStyle(
        color: appColors.sidebarPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      itemTextPadding: const EdgeInsets.only(left: 30),
      selectedItemTextPadding: const EdgeInsets.only(left: 30),
      itemDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.transparent),
      ),
      selectedItemDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: appColors.sidebarRing.withValues(alpha: 0.37),
        ),
        gradient: isDark
            ? LinearGradient(
                colors: [
                  appColors.sidebarPrimary.withValues(alpha: 0.1),
                  appColors.sidebarPrimary.withValues(alpha: 0.05),
                ],
              )
            : null,
        color: isDark ? null : appColors.sidebarAccent,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 30,
          )
        ],
      ),
      iconTheme: IconThemeData(
        color: appColors.sidebarForeground.withValues(alpha: 0.7),
        size: 20,
      ),
      selectedIconTheme: IconThemeData(
        color: appColors.sidebarPrimary,
        size: 20,
      ),
    );
  }

  SidebarXTheme _buildExtendedSidebarTheme(BuildContext context) {
    final appColors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SidebarXTheme(
      width: 280,
      decoration: BoxDecoration(
        gradient: isDark ? AppGradients.darkSidebarGradient : null,
        color: isDark ? null : appColors.sidebar,
      ),
      margin: const EdgeInsets.only(right: 10),
    );
  }

  Widget _buildSidebarHeader(bool extended) {
    final appColors = context.appColors;

    return Container(
      height: 100,
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      child: extended
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BrickChat Demo',
                  style: TextStyle(
                    color: appColors.sidebarForeground,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Modern Flutter architecture',
                  style: TextStyle(
                    color: appColors.sidebarForeground.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            )
          : Icon(
              Icons.chat,
              color: appColors.sidebarPrimary,
              size: 30,
            ),
    );
  }

  List<SidebarXItem> _buildSidebarItems() {
    return [
      SidebarXItem(
        icon: Icons.chat,
        label: 'Chat',
        onTap: () {
          // Chat functionality
        },
      ),
      const SidebarXItem(
        icon: Icons.search,
        label: 'Search',
      ),
      SidebarXItem(
        icon: Icons.palette,
        label: 'Themes',
        onTap: () {
          // Show theme options
        },
      ),
      const SidebarXItem(
        icon: Icons.settings,
        label: 'Settings',
      ),
      const SidebarXItem(
        icon: Icons.help,
        label: 'Help',
      ),
    ];
  }

  Widget _buildChatBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget body = Column(
      children: [
        Expanded(
          child: _buildMessageList(),
        ),
        _buildMessageInput(),
      ],
    );

    if (isDark) {
      return GradientContainer(
        gradient: AppGradients.darkBackgroundGradient,
        child: body,
      );
    }

    return body;
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        return _buildMessageBubble(_messages[index]);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final appColors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingXs),
      child: Row(
        mainAxisAlignment: message.isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isOwn) ...[
            _buildAvatar(message.author),
            const SizedBox(width: AppConstants.spacingSm),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: message.isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!message.isOwn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.author,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: appColors.mutedForeground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingMd,
                    vertical: AppConstants.spacingSm,
                  ),
                  decoration: BoxDecoration(
                    gradient: Theme.of(context).brightness == Brightness.dark
                        ? (message.isOwn
                            ? AppGradients.darkMessageBubbleGradient
                            : AppGradients.darkMessageBubbleOtherGradient)
                        : null,
                    color: Theme.of(context).brightness == Brightness.light
                        ? (message.isOwn
                            ? appColors.messageBubbleOwn
                            : appColors.messageBubble)
                        : null,
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  ),
                  child: Text(
                    message.text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: message.isOwn
                          ? appColors.messageTextOwn
                          : appColors.messageText,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: appColors.mutedForeground,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (message.isOwn) ...[
            const SizedBox(width: AppConstants.spacingSm),
            _buildAvatar(message.author),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(String name) {
    final appColors = context.appColors;

    return CircleAvatar(
      radius: 16,
      backgroundColor: appColors.accent,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: appColors.accentForeground,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Speech to text widget (shown when mic button is pressed)
          if (_showSpeechToText) ...[
            SpeechToTextWidget(
              onTextRecognized: (text) {
                if (text.isNotEmpty) {
                  _sendMessage(text: text);
                }
              },
              onCancel: () {
                setState(() {
                  _showSpeechToText = false;
                });
              },
              hintText: 'Speak your message...',
            ),
            const SizedBox(height: AppConstants.spacingSm),
          ],

          // Input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacingMd,
                      vertical: AppConstants.spacingSm,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: AppConstants.spacingSm),

              // Microphone button
              IconButton(
                onPressed: () {
                  setState(() {
                    _showSpeechToText = !_showSpeechToText;
                  });
                },
                icon: Icon(
                  _showSpeechToText ? Icons.keyboard : Icons.mic,
                  color: _showSpeechToText
                    ? Theme.of(context).colorScheme.primary
                    : null,
                ),
                tooltip: _showSpeechToText ? 'Hide voice input' : 'Voice input',
              ),

              const SizedBox(width: AppConstants.spacingXs),

              // Send button
              FloatingActionButton(
                onPressed: _sendMessage,
                mini: true,
                child: const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class ChatMessage {
  final String id;
  final String text;
  final bool isOwn;
  final DateTime timestamp;
  final String author;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isOwn,
    required this.timestamp,
    required this.author,
  });
}