import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidebarx/sidebarx.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:logging/logging.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/gradients.dart';
import 'dart:js_interop';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/theme_toggle.dart';
import '../../../shared/widgets/speech_to_text_widget.dart';
import '../../../shared/widgets/collapsible_reasoning_widget.dart';
import '../../../shared/widgets/footnotes_accordion.dart';
import '../../settings/presentation/settings_page.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/services/fastapi_service.dart';
import '../../../core/utils/tts_text_cleaner.dart';

class ChatHomePage extends ConsumerStatefulWidget {
  const ChatHomePage({super.key});

  @override
  ConsumerState<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends ConsumerState<ChatHomePage> {
  final _log = Logger('ChatHomePage');
  final List<ChatMessage> _messages = [];
  final List<Map<String, String>> _conversationHistory = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageInputFocus = FocusNode();
  bool _showSpeechToText = false;

  // Audio player state
  Audio? _currentAudio;
  String? _currentPlayingMessageId;
  bool _isAudioPlaying = false;
  bool _isAudioLoading = false; // Track if TTS is being generated

  // SidebarX controller
  late SidebarXController _sidebarController;

  @override
  void initState() {
    super.initState();
    _sidebarController = SidebarXController(selectedIndex: 0, extended: false);
    _loadInitialMessages();

  }

  @override
  void dispose() {
    _stopAudio();
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
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
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

      // Allow typing indicator to be visible for the full animation sequence
      await Future.delayed(const Duration(milliseconds: 2000));

      // Get response from FastAPI backend (streaming or non-streaming based on setting)
      final conversationContext = _prepareConversationContext();
      final useStreaming = ref.read(streamResultsProvider);

      if (useStreaming) {
        // Remove typing indicator and add empty message for streaming
        final assistantMessageId = 'assistant_${DateTime.now().millisecondsSinceEpoch}';
        final assistantMessage = ChatMessage(
          id: assistantMessageId,
          text: '',
          isOwn: false,
          timestamp: DateTime.now(),
          author: 'Assistant',
          isStreaming: true, // Mark as streaming
          footnotes: [], // Initialize empty footnotes list
        );

        setState(() {
          _messages.removeWhere((msg) => msg.id.startsWith('typing_'));
          _messages.add(assistantMessage);
        });

        // Streaming mode - show response word by word
        final responseBuffer = StringBuffer();
        List<Map<String, String>> footnotes = [];

        await for (final chunk in FastApiService.sendMessageStream(messageText, conversationContext)) {
          if (mounted) {
            // Handle content chunks
            if (chunk.containsKey('content')) {
              responseBuffer.write(chunk['content']);

              // Update the message text with accumulated response
              final messageIndex = _messages.indexWhere((msg) => msg.id == assistantMessageId);
              if (messageIndex != -1) {
                _messages[messageIndex].text = responseBuffer.toString();
                setState(() {});
                _scrollToBottom();
              }
            }
            // Handle footnotes
            else if (chunk.containsKey('footnotes')) {
              final footnotesList = chunk['footnotes'] as List<dynamic>;
              for (final footnote in footnotesList) {
                footnotes.add({
                  'id': footnote['id'].toString(),
                  'content': footnote['content'].toString(),
                });
              }

              // Update the message footnotes
              final messageIndex = _messages.indexWhere((msg) => msg.id == assistantMessageId);
              if (messageIndex != -1) {
                _messages[messageIndex].footnotes = footnotes;
                setState(() {});
              }
            }
            // Handle errors
            else if (chunk.containsKey('error')) {
              responseBuffer.write('Error: ${chunk['error']}');
              final messageIndex = _messages.indexWhere((msg) => msg.id == assistantMessageId);
              if (messageIndex != -1) {
                _messages[messageIndex].text = responseBuffer.toString();
                setState(() {});
              }
              break;
            }
          }
        }

        // Mark streaming as complete
        if (mounted) {
          final messageIndex = _messages.indexWhere((msg) => msg.id == assistantMessageId);
          if (messageIndex != -1) {
            _messages[messageIndex].isStreaming = false;
            setState(() {});

            // Auto-trigger TTS if eager mode is enabled (after streaming completes)
            final eagerMode = ref.read(eagerModeProvider);
            if (eagerMode && responseBuffer.isNotEmpty) {
              // Wait a brief moment for UI to settle, then play TTS
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && messageIndex != -1) {
                  _playTextToSpeech(_messages[messageIndex]);
                }
              });
            }
          }
        }

        // Add final response to conversation history
        if (mounted && responseBuffer.isNotEmpty) {
          _conversationHistory.add({
            'role': 'assistant',
            'content': responseBuffer.toString(),
          });
        }
      } else {
        // Non-streaming mode - get complete response first
        final response = await FastApiService.sendMessage(messageText, conversationContext);

        if (mounted) {
          // Parse footnotes from the response
          final parsedResponse = _parseFootnotesFromResponse(response);

          // Create assistant message with parsed response and footnotes
          final assistantMessage = ChatMessage(
            id: 'assistant_${DateTime.now().millisecondsSinceEpoch}',
            text: parsedResponse.text,
            isOwn: false,
            timestamp: DateTime.now(),
            author: 'Assistant',
            footnotes: parsedResponse.footnotes,
          );

          // Remove typing indicator and add complete response
          setState(() {
            _messages.removeWhere((msg) => msg.id.startsWith('typing_'));
            _messages.add(assistantMessage);
          });
          _scrollToBottom();

          // Add final response to conversation history
          if (response.isNotEmpty) {
            _conversationHistory.add({
              'role': 'assistant',
              'content': response,
            });

            // Auto-trigger TTS if eager mode is enabled
            final eagerMode = ref.read(eagerModeProvider);
            if (eagerMode) {
              // Wait a brief moment for UI to settle, then play TTS
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) {
                  _playTextToSpeech(assistantMessage);
                }
              });
            }
          }
        }
      }
    } catch (error) {
      // Remove typing indicator and show error message
      if (mounted) {
        setState(() {
          _messages.removeWhere((msg) => msg.id.startsWith('typing_'));
          _messages.add(ChatMessage(
            id: 'error_${DateTime.now().millisecondsSinceEpoch}',
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

  /// Parse footnotes from response text
  _ParsedFootnoteResponse _parseFootnotesFromResponse(String response) {
    // First, look for footnote definitions at the end of the message
    // Pattern: [^id]: content
    final footnoteDefinitionPattern = RegExp(
      r'\[\^([^\]]+)\]:\s*([^\n]+)',
      multiLine: true,
    );

    List<Map<String, String>> footnotes = [];
    String cleanedText = response;

    // Extract all footnote definitions
    final defMatches = footnoteDefinitionPattern.allMatches(response).toList();

    for (final match in defMatches) {
      final footnoteId = match.group(1) ?? '';
      final footnoteContent = match.group(2) ?? '';

      if (footnoteId.isNotEmpty && footnoteContent.isNotEmpty) {
        // Extract just the number from IDs like "Zqez-1" -> "1"
        final numberMatch = RegExp(r'(\d+)').firstMatch(footnoteId);
        final footnoteNumber = numberMatch?.group(0) ?? footnoteId;

        footnotes.add({
          'id': footnoteNumber,
          'content': footnoteContent.trim(),
        });
      }
    }

    // Remove footnote definitions from the text
    cleanedText = cleanedText.replaceAll(footnoteDefinitionPattern, '');

    // Now clean up the footnote references in the text
    // Pattern: [^id] or variations
    final footnoteReferencePattern = RegExp(
      r'\[\^([^\]]+)\](?!:)',
      multiLine: true,
    );

    // Replace footnote references with superscript numbers
    cleanedText = cleanedText.replaceAllMapped(footnoteReferencePattern, (match) {
      final footnoteId = match.group(1) ?? '';
      // Extract just the number from IDs like "Zqez-1" -> "1"
      final numberMatch = RegExp(r'(\d+)').firstMatch(footnoteId);
      final footnoteNumber = numberMatch?.group(0) ?? '1';

      // Convert to superscript
      final superscriptNumber = _getSuperscriptNumber(footnoteNumber);
      return '[$superscriptNumber](#footnote-$footnoteNumber)';
    });

    // Also handle any HTML-style footnotes that might exist
    final htmlFootnotePattern = RegExp(
      r'<sup\s*(?:id="footnote-(\d+)")?[^>]*>\s*(?:<a[^>]*>)?\s*(\d+)\s*(?:</a>)?\s*</sup>',
      multiLine: true,
      dotAll: true,
    );

    cleanedText = cleanedText.replaceAllMapped(htmlFootnotePattern, (match) {
      final footnoteNumber = match.group(2) ?? match.group(1) ?? '1';
      final superscriptNumber = _getSuperscriptNumber(footnoteNumber);
      return '[$superscriptNumber](#footnote-$footnoteNumber)';
    });

    return _ParsedFootnoteResponse(
      text: cleanedText.trim(),
      footnotes: footnotes,
    );
  }

  /// Convert regular number to Unicode superscript
  String _getSuperscriptNumber(String number) {
    const superscriptMap = {
      '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
      '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    };

    return number.split('').map((digit) =>
      superscriptMap[digit] ?? digit
    ).join();
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
                  title: Image.asset(
                    ref.isDarkMode
                        ? AppColors.darkLogo
                        : AppColors.lightLogo,
                    height: 30,
                    fit: BoxFit.contain,
                  ),
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
                  ref.isDarkMode ? AppConstants.appNameDark : AppConstants.appName,
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
    return SelectionArea(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          return _buildMessageBubble(_messages[index]);
        },
      ),
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
                      ? _buildTypingIndicator(context)
                      : message.isOwn
                          ? Text(
                              message.text,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: appColors.messageTextOwn,
                              ),
                            )
                          : CollapsibleReasoningWidget(
                              messageText: message.text == 'WELCOME_MESSAGE'
                                  ? (ref.isDarkMode ? 'Welcome to ${AppConstants.appNameDark}!' : 'Welcome to BrickChat!')
                                  : message.text,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                  color: appColors.messageText,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                                h1: TextStyle(
                                  color: appColors.messageText,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                h2: TextStyle(
                                  color: appColors.messageText,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                h3: TextStyle(
                                  color: appColors.messageText,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                code: TextStyle(
                                  backgroundColor: appColors.muted.withValues(alpha: 0.3),
                                  color: appColors.messageText,
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: appColors.muted.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: appColors.input.withValues(alpha: 0.3),
                                  ),
                                ),
                                strong: TextStyle(
                                  color: appColors.messageText,
                                  fontWeight: FontWeight.bold,
                                ),
                                em: TextStyle(
                                  color: appColors.messageText,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                ),
                // Footnotes accordion (only for assistant messages)
                if (!message.isOwn && message.footnotes.isNotEmpty)
                  FootnotesAccordion(
                    footnotes: message.footnotes,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        color: appColors.messageText,
                        fontSize: 12,
                        height: 1.4,
                      ),
                      code: TextStyle(
                        backgroundColor: appColors.muted.withValues(alpha: 0.3),
                        color: appColors.messageText,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                      strong: TextStyle(
                        color: appColors.messageText,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: message.isOwn ? MainAxisAlignment.end : MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(message.timestamp),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: appColors.mutedForeground,
                            fontSize: 10,
                          ),
                        ),
                        // Streaming indicator
                        if (message.isStreaming && !message.isOwn) ...[
                          const SizedBox(width: 8),
                          LoadingAnimationWidget.staggeredDotsWave(
                            color: appColors.accent,
                            size: 16,
                          ),
                        ],
                      ],
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
                                    await _writeToClipboard(text);
                                    copySuccess = true;
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

                          // Text-to-Speech button (headphones icon with play/pause/stop)
                          // Disable during streaming
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: message.isStreaming ? null : () {
                                  // Prevent multiple taps while loading or streaming
                                  if (!_isAudioLoading && !message.isStreaming) {
                                    _playTextToSpeech(message);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: message.isStreaming
                                        ? appColors.input.withValues(alpha: 0.05) // Disabled appearance during streaming
                                        : (_currentPlayingMessageId == message.id || (_isAudioLoading && _currentPlayingMessageId == message.id))
                                            ? appColors.accent.withValues(alpha: 0.2)
                                            : appColors.input.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: (_currentPlayingMessageId == message.id || (_isAudioLoading && _currentPlayingMessageId == message.id)) && !message.isStreaming
                                        ? Border.all(color: appColors.accent.withValues(alpha: 0.3), width: 1)
                                        : null,
                                  ),
                                  child: _isAudioLoading && _currentPlayingMessageId == message.id
                                      ? SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: appColors.accent,
                                          ),
                                        )
                                      : Icon(
                                          _currentPlayingMessageId == message.id && _isAudioPlaying
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          size: 12,
                                          color: message.isStreaming
                                              ? appColors.mutedForeground.withValues(alpha: 0.3) // Dimmed during streaming
                                              : _currentPlayingMessageId == message.id
                                                  ? appColors.accent
                                                  : appColors.mutedForeground,
                                        ),
                                ),
                              ),
                              if (_currentPlayingMessageId == message.id) ...[
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: _stopAudio,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: appColors.input.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      Icons.stop,
                                      size: 12,
                                      color: appColors.mutedForeground,
                                    ),
                                  ),
                                ),
                              ],
                            ],
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
                child: TextField(
                  controller: _messageController,
                  focusNode: _messageInputFocus,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                      borderSide: BorderSide(
                        color: context.appColors.input,
                        width: 1.0,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                      borderSide: BorderSide(
                        color: context.appColors.input,
                        width: 1.0,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                      borderSide: BorderSide(
                        color: context.appColors.accent,
                        width: 2.0,
                      ),
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

  void _playTextToSpeech(ChatMessage message) async {
    if (!mounted) return;

    // Don't play TTS if message is still streaming
    if (message.isStreaming) {
      return;
    }

    // If this message is already playing, pause it
    if (_currentPlayingMessageId == message.id && _isAudioPlaying) {
      _pauseAudio();
      return;
    }

    // If this message was paused, resume it
    if (_currentPlayingMessageId == message.id && !_isAudioPlaying && _currentAudio != null) {
      _resumeAudio();
      return;
    }

    // Stop any currently playing audio
    _stopAudio();

    // Set loading state
    setState(() {
      _isAudioLoading = true;
      _currentPlayingMessageId = message.id;
    });

    try {
      // Log the raw text before cleaning
      print('===== TTS RAW TEXT (BEFORE CLEANING) =====');
      print(message.text);
      print('==========================================');

      // Clean text for TTS (remove think tags, markdown, special characters)
      final cleanedText = TtsTextCleaner.cleanForTts(message.text);

      // Log the cleaned text being sent to TTS
      print('===== TTS CLEANED TEXT (SENT TO TTS) =====');
      print(cleanedText);
      print('===========================================');

      // Skip TTS if cleaned text is empty
      if (cleanedText.isEmpty) {
        if (mounted) {
          setState(() {
            _isAudioLoading = false;
            _currentPlayingMessageId = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No speakable content in message',
                style: TextStyle(fontSize: 12, color: Colors.white),
              ),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.orange.withValues(alpha: 0.85),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Show loading snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Generating audio...',
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
          duration: Duration(seconds: 3),
          backgroundColor: Colors.blue.withValues(alpha: 0.85),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.snackBarRadius),
          ),
          elevation: 4,
          width: MediaQuery.of(context).size.width * AppConstants.snackBarWidthFactor,
        ),
      );

      // Get TTS settings
      final ttsProvider = ref.read(ttsProviderProvider);
      final ttsVoice = ref.read(ttsVoiceProvider);

      // Call backend TTS API with cleaned text
      final response = await FastApiService.requestTts(
        cleanedText,
        provider: ttsProvider,
        voice: ttsVoice,
      );

      if (response.statusCode == 200 && mounted) {
        _log.info('TTS response received: ${response.bodyBytes.length} bytes');

        // Clear loading state and snackbar
        setState(() {
          _isAudioLoading = false;
        });
        ScaffoldMessenger.of(context).clearSnackBars();

        // Play audio using web audio API
        if (kIsWeb) {
          try {
            await _playAudioWeb(response.bodyBytes, message.id);

            // Show success snackbar only if playback started
            if (mounted) {
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
          } catch (playError) {
            _log.severe('Audio playback error: $playError');
            throw Exception('Audio playback failed: $playError');
          }
        }
      } else {
        throw Exception('TTS request failed: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAudioLoading = false;
          _currentPlayingMessageId = null;
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to play audio: $e',
              style: TextStyle(fontSize: 12, color: Colors.white),
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red.withValues(alpha: 0.85),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _pauseAudio() {
    if (_currentAudio != null && kIsWeb) {
      _currentAudio!.pause();
      setState(() {
        _isAudioPlaying = false;
      });
    }
  }

  void _resumeAudio() {
    if (_currentAudio != null && kIsWeb) {
      _currentAudio!.play();
      setState(() {
        _isAudioPlaying = true;
      });
    }
  }

  void _stopAudio() {
    if (_currentAudio != null && kIsWeb) {
      _currentAudio!.pause();
      _currentAudio!.currentTime = 0.0;
      _currentAudio = null;
      setState(() {
        _currentPlayingMessageId = null;
        _isAudioPlaying = false;
        _isAudioLoading = false;
      });
    }
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

  Widget _buildTypingIndicator(BuildContext context) {
    final appColors = context.appColors;

    return Container(
      key: const ValueKey('typing_indicator'),
      constraints: const BoxConstraints(
        minHeight: 40,
        maxWidth: 300,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: appColors.messageBubble,
        borderRadius: BorderRadius.circular(18),
      ),
      child: IntrinsicWidth(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: AnimatedTextKit(
                animatedTexts: [
                  TyperAnimatedText(
                    'Assistant is working...',
                    textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: appColors.messageText,
                    ),
                    speed: const Duration(milliseconds: 100),
                  ),
                  TyperAnimatedText(
                    'Contacting the right agent/squad...',
                    textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: appColors.messageText,
                    ),
                    speed: const Duration(milliseconds: 80),
                  ),
                  TyperAnimatedText(
                    'Channeling controls and gathering responses...',
                    textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: appColors.messageText,
                    ),
                    speed: const Duration(milliseconds: 70),
                  ),
                  TyperAnimatedText(
                    'Resolving response...',
                    textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: appColors.messageText,
                    ),
                    speed: const Duration(milliseconds: 90),
                  ),
                ],
                totalRepeatCount: 1,
                pause: const Duration(milliseconds: 800),
                displayFullTextOnTap: true,
                stopPauseOnTap: true,
              ),
            ),
            const SizedBox(width: 8),
            LoadingAnimationWidget.threeArchedCircle(
              color: appColors.messageText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playAudioWeb(List<int> audioBytes, String messageId) async {
    _log.fine('Audio playback started - ${audioBytes.length} bytes');

    // Convert bytes to base64
    final base64Audio = base64Encode(audioBytes);
    _log.fine('Base64 audio length: ${base64Audio.length}');

    final dataUrl = 'data:audio/mpeg;base64,$base64Audio';
    _log.fine('Data URL created (first 100 chars): ${dataUrl.substring(0, 100)}...');

    // Create audio element with src in constructor (more reliable)
    final audio = Audio(dataUrl);
    _log.fine('Audio element created with src');

    // Add event listeners for debugging
    audio.onerror = ((JSAny? error) {
      _log.warning('Audio error event: $error');
      _log.warning('Audio src at error: ${audio.src}');
    }).toJS;

    audio.onloadeddata = ((JSAny? event) {
      _log.fine('Audio loaded data event');
    }).toJS;

    audio.oncanplay = ((JSAny? event) {
      _log.fine('Audio can play event');
    }).toJS;

    audio.onended = ((JSAny? event) {
      _log.fine('Audio ended event');
      if (mounted) {
        setState(() {
          _currentAudio = null;
          _currentPlayingMessageId = null;
          _isAudioPlaying = false;
        });
      }
    }).toJS;

    // Store reference to current audio
    _currentAudio = audio;
    _currentPlayingMessageId = messageId;
    _log.fine('Audio reference stored');

    // Try to play with better error handling
    _log.fine('About to call play()...');
    try {
      // Load the audio first
      audio.load();
      _log.fine('Audio load() called');

      // Small delay to allow loading
      await Future.delayed(Duration(milliseconds: 100));

      final playPromise = audio.play();
      _log.fine('play() called, awaiting promise...');
      await playPromise.toDart;
      _log.info('Audio play promise resolved');

      _isAudioPlaying = true;
      _log.info('Audio playing successfully');

      // Update state to reflect playback
      if (mounted) {
        setState(() {});
      }
    } catch (playError) {
      _log.severe('Audio play error: $playError');
      _log.severe('Error type: ${playError.runtimeType}');

      // Check if it's an autoplay error
      final errorStr = playError.toString().toLowerCase();
      if (errorStr.contains('autoplay') || errorStr.contains('notallowederror')) {
        throw Exception('Browser blocked autoplay. Please interact with the page first.');
      }

      _currentAudio = null;
      _currentPlayingMessageId = null;
      _isAudioPlaying = false;
      if (mounted) {
        setState(() {});
      }
      rethrow;
    }

    _log.fine('Audio playback setup complete');
  }

}

class ChatMessage {
  final String id;
  String text; // Made mutable for streaming updates
  final bool isOwn;
  final DateTime timestamp;
  final String author;
  bool? isLiked; // null = no rating, true = liked, false = disliked
  bool isStreaming; // Track if this message is currently being streamed
  List<Map<String, String>> footnotes; // List of footnotes with id and content (mutable for streaming)

  ChatMessage({
    required this.id,
    required this.text,
    required this.isOwn,
    required this.timestamp,
    required this.author,
    this.isLiked,
    this.isStreaming = false,
    List<Map<String, String>>? footnotes,
  }) : footnotes = footnotes ?? [];
}

// Helper class for parsing footnotes from response
class _ParsedFootnoteResponse {
  final String text;
  final List<Map<String, String>> footnotes;

  _ParsedFootnoteResponse({
    required this.text,
    required this.footnotes,
  });
}

// JS interop for clipboard access
@JS('navigator.clipboard.writeText')
external JSPromise<JSAny?> _writeTextToClipboard(String text);

Future<void> _writeToClipboard(String text) async {
  await _writeTextToClipboard(text).toDart;
}

// JS interop for audio playback
@JS('Audio')
@staticInterop
class Audio {
  external factory Audio([String? src]);
}

extension AudioElement on Audio {
  external set src(String src);
  external String get src;
  external set currentTime(double value);
  external double get currentTime;
  external JSPromise<JSAny?> play();
  external void pause();
  external void load();
  external set onerror(JSFunction callback);
  external set onloadeddata(JSFunction callback);
  external set oncanplay(JSFunction callback);
  external set onended(JSFunction callback);
}