import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidebarx/sidebarx.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:glowy_borders/glowy_borders.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/gradients.dart';
import 'dart:html' as html show window, navigator;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/theme_toggle.dart';
import '../../../shared/widgets/speech_to_text_widget.dart';
import '../../settings/presentation/settings_page.dart';
import '../../../core/services/fastapi_service.dart';

class ChatHomePage extends ConsumerStatefulWidget {
  const ChatHomePage({super.key});

  @override
  ConsumerState<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends ConsumerState<ChatHomePage> {
  final List<ChatMessage> _messages = [];
  final List<Map<String, String>> _conversationHistory = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageInputFocus = FocusNode();
  bool _showSpeechToText = false;
  bool _isTextFieldFocused = false;

  // SidebarX controller
  late SidebarXController _sidebarController;

  @override
  void initState() {
    super.initState();
    _sidebarController = SidebarXController(selectedIndex: 0, extended: true);
    _loadInitialMessages();

    // Add focus listener for glowing effect
    _messageInputFocus.addListener(() {
      setState(() {
        _isTextFieldFocused = _messageInputFocus.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageInputFocus.dispose();
    _sidebarController.dispose();
    super.dispose();
  }

  void _loadInitialMessages() {
    setState(() {
      _messages.addAll([
        ChatMessage(
          id: '1',
          text: 'WELCOME_MESSAGE', // Placeholder that will be replaced in UI
          isOwn: false,
          timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
          author: 'Assistant',
        ),
      ]);
    });
  }

  void _sendMessage({String? text}) async {
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

    // Add user message to conversation history
    _conversationHistory.add({
      'role': 'user',
      'content': messageText,
    });

    _scrollToBottom();

    try {
      // Show typing indicator
      final typingMessage = ChatMessage(
        id: 'typing_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Assistant is typing...',
        isOwn: false,
        timestamp: DateTime.now(),
        author: 'Assistant',
      );

      setState(() {
        _messages.add(typingMessage);
      });
      _scrollToBottom();

      // Get response from FastAPI backend with conversation context
      final conversationContext = _prepareConversationContext();
      final responseText = await FastApiService.sendMessage(messageText, conversationContext);

      // Remove typing indicator
      setState(() {
        _messages.removeWhere((msg) => msg.id.startsWith('typing_'));
      });

      if (mounted) {
        final assistantMessage = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: responseText,
          isOwn: false,
          timestamp: DateTime.now(),
          author: 'Assistant',
        );

        setState(() {
          _messages.add(assistantMessage);
        });

        // Add assistant response to conversation history
        _conversationHistory.add({
          'role': 'assistant',
          'content': responseText,
        });

        _scrollToBottom();
      }
    } catch (error) {
      // Remove typing indicator and show error message
      if (mounted) {
        setState(() {
          _messages.removeWhere((msg) => msg.id.startsWith('typing_'));
          _messages.add(ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: 'Sorry, I encountered an error: ${error.toString()}',
            isOwn: false,
            timestamp: DateTime.now(),
            author: 'Assistant',
          ));
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: AppConstants.themeTransitionDuration,
        curve: Curves.easeOut,
      );
    }
  }

  List<Map<String, String>> _prepareConversationContext() {
    // Keep the most recent 5 messages (10 total - 5 user + 5 assistant)
    const int maxRecentMessages = AppConstants.maxRecentMessages;

    if (_conversationHistory.length <= maxRecentMessages) {
      return _conversationHistory;
    }

    // Get older messages that need summarization
    List<Map<String, String>> olderMessages = _conversationHistory
        .take(_conversationHistory.length - maxRecentMessages)
        .toList();

    // Get recent messages to keep verbatim
    List<Map<String, String>> recentMessages = _conversationHistory
        .skip(_conversationHistory.length - maxRecentMessages)
        .toList();

    // Create summary of older conversation
    String summary = _summarizeOlderContext(olderMessages);

    // Return context with summary + recent messages
    List<Map<String, String>> context = [];
    if (summary.isNotEmpty) {
      context.add({
        'role': 'system',
        'content': 'Previous conversation summary: $summary'
      });
    }
    context.addAll(recentMessages);

    return context;
  }

  String _summarizeOlderContext(List<Map<String, String>> olderMessages) {
    if (olderMessages.isEmpty) return '';

    List<String> summaryPoints = [];
    for (int i = 0; i < olderMessages.length; i += 2) {
      if (i + 1 < olderMessages.length) {
        String userMsg = olderMessages[i]['content'] ?? '';
        String assistantMsg = olderMessages[i + 1]['content'] ?? '';

        // Create brief summary of the exchange
        String userTopic = userMsg.length > AppConstants.messagePreviewLimit
            ? '${userMsg.substring(0, AppConstants.messagePreviewLimit)}...'
            : userMsg;
        String assistantTopic = assistantMsg.length > AppConstants.messagePreviewLimit
            ? '${assistantMsg.substring(0, AppConstants.messagePreviewLimit)}...'
            : assistantMsg;

        summaryPoints.add('User asked about: $userTopic. Assistant responded: $assistantTopic');
      }
    }

    return summaryPoints.join(' | ');
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
                  title: Text(ref.isDarkMode ? 'fBchat' : AppConstants.appName),
                  centerTitle: false,
                  actions: [
                    const ThemeToggle(),
                    const SizedBox(width: AppConstants.spacingSm),
                  ],
                ),
                Divider(color: context.appColors.sidebarBorder, height: 1),
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
      width: AppConstants.sidebarWidth,
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
      height: AppConstants.profileSectionHeight,
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      child: extended
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ref.isDarkMode ? 'fBchat' : 'BrickChat',
                  style: TextStyle(
                    color: appColors.sidebarForeground,
                    fontWeight: FontWeight.w600,
                    fontSize: AppConstants.profileNameFontSize,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  ref.isDarkMode ? AppConstants.appCaptionDark : AppConstants.appCaption,
                  style: TextStyle(
                    color: appColors.sidebarForeground.withValues(alpha: AppConstants.sidebarBackgroundAlpha),
                    fontSize: AppConstants.profileStatusFontSize,
                  ),
                ),
              ],
            )
          : Icon(
              Icons.chat,
              color: appColors.sidebarPrimary,
              size: AppConstants.profileIconSize,
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
        icon: Icons.settings,
        label: 'Settings',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const SettingsPage(),
            ),
          );
        },
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
                  child: message.id.startsWith('typing_')
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: AnimatedTextKit(
                                animatedTexts: [
                                  TypewriterAnimatedText(
                                    'Assistant is working...',
                                    textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: appColors.messageText,
                                    ),
                                    speed: const Duration(milliseconds: 100),
                                  ),
                                  TypewriterAnimatedText(
                                    'Assistant is contacting your agent squad...',
                                    textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: appColors.messageText,
                                    ),
                                    speed: const Duration(milliseconds: 80),
                                  ),
                                  TypewriterAnimatedText(
                                    'Assistant is collaborating on your task...',
                                    textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: appColors.messageText,
                                    ),
                                    speed: const Duration(milliseconds: 80),
                                  ),
                                ],
                                totalRepeatCount: 1,
                                pause: const Duration(milliseconds: 1500),
                                displayFullTextOnTap: true,
                                stopPauseOnTap: true,
                                onFinished: () {
                                  // This will be called when animation finishes
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  appColors.messageText.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        )
                      : message.isOwn
                          ? Text(
                              message.text,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: appColors.messageTextOwn,
                              ),
                            )
                          : MarkdownBody(
                              data: message.text == 'WELCOME_MESSAGE'
                                  ? (ref.isDarkMode ? 'Welcome to fBchat!' : 'Welcome to BrickChat!')
                                  : message.text,
                              styleSheet: MarkdownStyleSheet(
                                p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: appColors.messageText,
                                ),
                                a: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                                strong: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: appColors.messageText,
                                  fontWeight: FontWeight.bold,
                                ),
                                em: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: appColors.messageText,
                                  fontStyle: FontStyle.italic,
                                ),
                                code: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: appColors.messageText,
                                  backgroundColor: appColors.input.withValues(alpha: 0.1),
                                  fontFamily: 'monospace',
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: appColors.input.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onTapLink: (text, href, title) async {
                                if (href != null) {
                                  final uri = Uri.parse(href);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                }
                              },
                            ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: message.isOwn ? MainAxisAlignment.end : MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatTime(message.timestamp),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: appColors.mutedForeground,
                        fontSize: 10,
                      ),
                    ),
                    if (!message.isOwn && !message.id.startsWith('typing_'))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Like button (thumbs up)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                message.isLiked = message.isLiked == true ? null : true;
                              });
                              _showFeedbackSnackBar(true, message.isLiked == true);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: message.isLiked == true
                                    ? appColors.accent.withValues(alpha: 0.2)
                                    : appColors.input.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: message.isLiked == true
                                    ? Border.all(color: appColors.accent.withValues(alpha: 0.3), width: 1)
                                    : null,
                              ),
                              child: Icon(
                                Icons.thumb_up,
                                size: 12,
                                color: message.isLiked == true
                                    ? appColors.accent
                                    : appColors.mutedForeground,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Dislike button (thumbs down)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                message.isLiked = message.isLiked == false ? null : false;
                              });
                              _showFeedbackSnackBar(false, message.isLiked == false);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: message.isLiked == false
                                    ? Colors.red.withValues(alpha: 0.2)
                                    : appColors.input.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: message.isLiked == false
                                    ? Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1)
                                    : null,
                              ),
                              child: Icon(
                                Icons.thumb_down,
                                size: 12,
                                color: message.isLiked == false
                                    ? Colors.red
                                    : appColors.mutedForeground,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Copy button
                          GestureDetector(
                            onTap: () async {
                              try {
                                final text = message.text;

                                bool copySuccess = false;

                                // Try native web clipboard API first (more reliable for web)
                                if (kIsWeb) {
                                  try {
                                    final nav = html.window.navigator;
                                    if (nav.clipboard != null) {
                                      await nav.clipboard!.writeText(text);
                                      copySuccess = true;
                                    }
                                  } catch (webError) {
                                    // Fall through to Flutter clipboard
                                  }
                                }

                                // Fallback to Flutter's clipboard service if native API failed
                                if (!copySuccess) {
                                  await Clipboard.setData(ClipboardData(text: text));
                                }
                                if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            AppConstants.copyMessage,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white,
                                            ),
                                            softWrap: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                    duration: AppConstants.snackBarDuration,
                                    backgroundColor: appColors.accent.withValues(alpha: 0.85),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppConstants.snackBarRadius),
                                    ),
                                    elevation: 4,
                                    width: MediaQuery.of(context).size.width * AppConstants.snackBarWidthFactor,
                                  ),
                                );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Clipboard access blocked by browser. Text: ${message.text}',
                                        style: TextStyle(
                                          fontSize: AppConstants.snackBarFontSize,
                                          color: Colors.white,
                                        ),
                                      ),
                                      duration: Duration(milliseconds: 3000), // Longer duration to read the text
                                      backgroundColor: Colors.orange.withValues(alpha: AppConstants.accentAlpha),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(AppConstants.snackBarRadius),
                                      ),
                                      width: MediaQuery.of(context).size.width * 0.6, // Wider to show full text
                                    ),
                                  );
                                }
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: appColors.input.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                Icons.copy,
                                size: 12,
                                color: appColors.mutedForeground,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Text-to-Speech button (headphones icon)
                          GestureDetector(
                            onTap: () {
                              _playTextToSpeech(message.text);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: appColors.input.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                Icons.headphones,
                                size: 12,
                                color: appColors.mutedForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
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
                child: AnimatedGradientBorder(
                  borderSize: 2,
                  glowSize: _isTextFieldFocused ? 8 : 4,
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  gradientColors: _buildGlowColors(),
                  animationTime: 2000,
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageInputFocus,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[900]?.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.9),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacingMd,
                        vertical: AppConstants.spacingSm,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
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

  void _playTextToSpeech(String text) {
    if (!mounted) return;

    // TODO: Implement text-to-speech API call to backend
    // This will eventually call the backend API route for text-to-speech
    // For now, show a placeholder snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.volume_up,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                AppConstants.playingMessage,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                softWrap: true,
              ),
            ),
          ],
        ),
        duration: AppConstants.snackBarShortDuration,
        backgroundColor: Colors.green.withValues(alpha: 0.85),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.snackBarRadius),
        ),
        elevation: 4,
        width: MediaQuery.of(context).size.width * AppConstants.snackBarWidthFactor,
      ),
    );
  }

  void _showFeedbackSnackBar(bool isLike, bool isActive) {
    final appColors = context.appColors;
    if (!mounted) return;

    String message;
    IconData icon;
    Color backgroundColor;

    if (isActive) {
      if (isLike) {
        message = AppConstants.feedbackThanks;
        icon = Icons.thumb_up;
        backgroundColor = appColors.accent;
      } else {
        message = AppConstants.feedbackNoted;
        icon = Icons.thumb_down;
        backgroundColor = Colors.red;
      }
    } else {
      message = AppConstants.feedbackRemoved;
      icon = Icons.undo;
      backgroundColor = appColors.mutedForeground;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                softWrap: true,
              ),
            ),
          ],
        ),
        duration: AppConstants.snackBarShortDuration,
        backgroundColor: backgroundColor.withValues(alpha: 0.85),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.snackBarRadius),
        ),
        elevation: 4,
        width: MediaQuery.of(context).size.width * AppConstants.snackBarWidthFactor,
      ),
    );
  }

  List<Color> _buildGlowColors() {
    final appColors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isTextFieldFocused) {
      // More vibrant glow when focused
      if (isDark) {
        return [
          appColors.accent.withValues(alpha: 0.8),
          appColors.accentForeground.withValues(alpha: 0.6),
          Colors.blue.withValues(alpha: 0.7),
          appColors.accent.withValues(alpha: 0.5),
        ];
      } else {
        return [
          appColors.accent.withValues(alpha: 0.7),
          Colors.blue[400]!.withValues(alpha: 0.6),
          appColors.accentForeground.withValues(alpha: 0.5),
          appColors.accent.withValues(alpha: 0.4),
        ];
      }
    } else {
      // Subtle glow when not focused
      if (isDark) {
        return [
          appColors.accent.withValues(alpha: 0.3),
          appColors.mutedForeground.withValues(alpha: 0.2),
          Colors.blue.withValues(alpha: 0.2),
          appColors.accent.withValues(alpha: 0.1),
        ];
      } else {
        return [
          appColors.accent.withValues(alpha: 0.2),
          Colors.blue[300]!.withValues(alpha: 0.2),
          appColors.mutedForeground.withValues(alpha: 0.1),
          appColors.accent.withValues(alpha: 0.1),
        ];
      }
    }
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
  bool? isLiked; // null = no rating, true = liked, false = disliked

  ChatMessage({
    required this.id,
    required this.text,
    required this.isOwn,
    required this.timestamp,
    required this.author,
    this.isLiked,
  });
}