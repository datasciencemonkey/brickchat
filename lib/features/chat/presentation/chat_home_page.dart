import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidebarx/sidebarx.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:logging/logging.dart';
import 'package:file_selector/file_selector.dart';
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
import '../../../shared/widgets/footnotes_accordion.dart'; // Now exports SourcesAccordion
import '../../../shared/widgets/particles_widget.dart';
import '../../settings/presentation/settings_page.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/services/fastapi_service.dart';
import 'chat_history_page.dart';
import 'widgets/welcome_hero_screen.dart';
import 'widgets/document_chip.dart';
import '../providers/documents_provider.dart';

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
  String? _currentThreadId; // Track current thread ID from backend
  final String _userId = "dev_user"; // Default user ID
  String? _currentAgentEndpoint; // Track current agent endpoint
  bool _showWelcomeScreen = true; // Track if welcome screen should be shown

  // Audio player state
  Audio? _currentAudio;
  String? _currentPlayingMessageId;
  bool _isAudioPlaying = false;
  bool _isAudioLoading = false; // Track if TTS is being generated
  bool _isStreamingTts = false; // Track if streaming TTS is active
  bool _streamingNetworkDone = false; // Track if SSE stream has completed (all chunks received)
  final Map<String, List<int>> _ttsAudioCache = {}; // Cache TTS audio bytes per message ID
  final List<List<int>> _streamingAudioQueue = []; // Queue for streaming audio chunks
  bool _isPlayingFromQueue = false; // Track if we're playing from the queue

  // SidebarX controller
  late SidebarXController _sidebarController;

  @override
  void initState() {
    super.initState();
    _sidebarController = SidebarXController(selectedIndex: 0, extended: false);
    // Don't load initial messages on welcome screen
    _loadAgentEndpoint();
  }

  Future<void> _loadAgentEndpoint() async {
    try {
      final config = await FastApiService.getChatConfig();
      if (mounted) {
        setState(() {
          _currentAgentEndpoint = config['agent_endpoint'];
        });
      }
    } catch (e) {
      _log.warning('Failed to load agent endpoint: $e');
    }
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

  void _toggleVoiceInput() {
    setState(() {
      _showSpeechToText = !_showSpeechToText;
    });
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

  void _createNewThread() {
    setState(() {
      // Clear all messages
      _messages.clear();

      // Clear conversation history
      _conversationHistory.clear();

      // Reset thread ID
      _currentThreadId = null;

      // Clear the text input
      _messageController.clear();

      // Stop any playing audio
      _stopAudio();

      // Hide speech to text if showing
      _showSpeechToText = false;

      // Show welcome screen again
      _showWelcomeScreen = true;

      // Clear documents
      ref.read(documentsProvider.notifier).clear();
    });

    // Show confirmation snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'New conversation started',
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
          duration: Duration(seconds: 2),
          backgroundColor: context.appColors.accent.withValues(alpha: 0.85),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.snackBarRadius),
          ),
          elevation: 4,
          width: MediaQuery.of(context).size.width * AppConstants.snackBarWidthFactor,
        ),
      );
    }
  }

  void _loadThreadConversation(String? threadId, List<Map<String, dynamic>> messages) async {
    if (threadId == null || threadId == 'null') {
      // Start new thread
      _createNewThread();
      return;
    }

    setState(() {
      // Clear current messages
      _messages.clear();
      _conversationHistory.clear();

      // Set the thread ID
      _currentThreadId = threadId;

      // Stop any playing audio
      _stopAudio();

      // Hide speech to text if showing
      _showSpeechToText = false;

      // Hide welcome screen when loading a thread
      _showWelcomeScreen = false;

      // Extract agent endpoint from the last assistant message
      _currentAgentEndpoint = null;
      for (final message in messages.reversed) {
        if (message['message_role'] == 'assistant' && message['agent_endpoint'] != null) {
          _currentAgentEndpoint = message['agent_endpoint'];
          break;
        }
      }

      // Load messages from the thread
      for (final message in messages) {
        final isUserMessage = message['message_role'] == 'user';
        final messageId = 'loaded_${message['message_id'] ?? DateTime.now().millisecondsSinceEpoch}';
        final messageContent = message['message_content'] ?? '';

        // Debug logging
        print('Loading message: role=${message['message_role']}, content_length=${messageContent.length}, first_100_chars=${messageContent.length > 100 ? messageContent.substring(0, 100) : messageContent}');

        // Parse footnotes from assistant messages
        List<Map<String, String>> footnotes = [];
        String processedContent = messageContent;

        if (!isUserMessage && messageContent.contains('[^')) {
          // Extract footnotes from the content
          final parsedResponse = _parseFootnotesFromText(messageContent);
          processedContent = parsedResponse.text;
          footnotes = parsedResponse.footnotes;
        }

        // Add to messages list for display
        _messages.add(ChatMessage(
          id: messageId,
          text: processedContent,
          isOwn: isUserMessage,
          timestamp: message['created_at'] != null
              ? DateTime.parse(message['created_at'])
              : DateTime.now(),
          author: isUserMessage ? 'You' : 'Assistant',
          threadId: threadId,
          messageId: message['message_id'],
          agentEndpoint: message['agent_endpoint'],
          footnotes: footnotes,
        ));

        // Add to conversation history for context
        _conversationHistory.add({
          'role': message['message_role'] ?? 'user',
          'content': message['message_content'] ?? '',
        });
      }

      // If no messages, add welcome message
      if (_messages.isEmpty) {
        _loadInitialMessages();
      }
    });

    // Load documents for this thread if any
    final docs = await FastApiService.getThreadDocuments(threadId);
    ref.read(documentsProvider.notifier).loadFromBackend(docs);

    // Update endpoint if documents present
    if (docs.isNotEmpty) {
      setState(() {
        _currentAgentEndpoint = 'claude-opus-4-5';
      });
    }

    // Scroll to bottom after loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _sendMessage({String? text}) async {
    final messageText = text ?? _messageController.text.trim();
    if (messageText.isEmpty) return;

    // Upload any pending documents first
    final pendingDocs = ref.read(documentsProvider.notifier).pendingUploads;
    if (pendingDocs.isNotEmpty) {
      // Mark as uploading
      for (final doc in pendingDocs) {
        ref.read(documentsProvider.notifier).setUploading(doc.filename, true);
      }

      // Upload to backend
      final uploadResult = await FastApiService.uploadDocuments(
        files: pendingDocs.map((doc) => {
          'filename': doc.filename,
          'bytes': doc.bytes!,
        }).toList(),
        threadId: _currentThreadId,
      );

      if (uploadResult.containsKey('error')) {
        // Handle upload error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload failed: ${uploadResult['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        // Reset uploading state
        for (final doc in pendingDocs) {
          ref.read(documentsProvider.notifier).setUploading(doc.filename, false);
        }
        return;
      }

      // Update thread ID if new
      _currentThreadId = uploadResult['thread_id'];

      // Mark documents as uploaded
      final uploadedDocs = uploadResult['documents'] as List<dynamic>? ?? [];
      for (final doc in uploadedDocs) {
        ref.read(documentsProvider.notifier).markUploaded(
          doc['filename'],
          DateTime.now().toIso8601String(),
        );
      }

      // Update endpoint display
      if (uploadResult['endpoint'] != null) {
        setState(() {
          _currentAgentEndpoint = uploadResult['endpoint'];
        });
      }
    }

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
      _showWelcomeScreen = false; // Hide welcome screen when sending first message
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
        List<Map<String, dynamic>> citations = [];

        await for (final chunk in FastApiService.sendMessageStream(
          messageText,
          conversationHistory: conversationContext,
          threadId: _currentThreadId,
          userId: _userId,
        )) {
          if (mounted) {
            // Handle metadata (thread_id, message_ids, agent_endpoint)
            if (chunk.containsKey('metadata')) {
              final metadata = chunk['metadata'] as Map<String, dynamic>;
              setState(() {
                _currentThreadId = metadata['thread_id'];
                _currentAgentEndpoint = metadata['agent_endpoint'];
              });
              // Update user message with backend message ID
              final userMsgIndex = _messages.indexWhere((msg) => msg.id == message.id);
              if (userMsgIndex != -1) {
                _messages[userMsgIndex].threadId = _currentThreadId;
                _messages[userMsgIndex].messageId = metadata['user_message_id'];
              }
              // Update assistant message with agent endpoint
              final assistantMsgIndex = _messages.indexWhere((msg) => msg.id == assistantMessageId);
              if (assistantMsgIndex != -1) {
                _messages[assistantMsgIndex].agentEndpoint = _currentAgentEndpoint;
              }
            }
            // Handle assistant message ID
            else if (chunk.containsKey('assistant_message_id')) {
              final assistantMsgIndex = _messages.indexWhere((msg) => msg.id == assistantMessageId);
              if (assistantMsgIndex != -1) {
                _messages[assistantMsgIndex].threadId = _currentThreadId;
                _messages[assistantMsgIndex].messageId = chunk['assistant_message_id'];
              }
            }
            // Handle content chunks
            else if (chunk.containsKey('content')) {
              responseBuffer.write(chunk['content']);

              // Update the message text with accumulated response
              final messageIndex = _messages.indexWhere((msg) => msg.id == assistantMessageId);
              if (messageIndex != -1) {
                _messages[messageIndex].text = responseBuffer.toString();
                setState(() {});
                _scrollToBottom();
              }
            }
            // Handle reasoning (comes after content is done, needs to be prepended)
            else if (chunk.containsKey('reasoning')) {
              final reasoning = chunk['reasoning'] as String;
              // Prepend reasoning to the response (it comes with <think> tags from backend)
              final currentContent = responseBuffer.toString();
              responseBuffer.clear();
              responseBuffer.write(reasoning);
              responseBuffer.write(currentContent);

              // Update the message text with reasoning prepended
              final messageIndex = _messages.indexWhere((msg) => msg.id == assistantMessageId);
              if (messageIndex != -1) {
                _messages[messageIndex].text = responseBuffer.toString();
                setState(() {});
              }
            }
            // Handle citations (sources from the model)
            else if (chunk.containsKey('citations')) {
              final citationsList = chunk['citations'] as List<dynamic>;
              for (final citation in citationsList) {
                citations.add({
                  'id': citation['id']?.toString() ?? '',
                  'title': citation['title']?.toString() ?? 'Source',
                  'url': citation['url']?.toString() ?? '',
                  'content_index': citation['content_index'] ?? 0,
                });
              }

              // Update the message citations
              final messageIndex = _messages.indexWhere((msg) => msg.id == assistantMessageId);
              if (messageIndex != -1) {
                _messages[messageIndex].citations = citations;

                // Post-process text to add inline citation markers based on content_index
                final annotatedText = _insertCitationMarkers(
                  responseBuffer.toString(),
                  citations,
                );
                _messages[messageIndex].text = annotatedText;
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
            _log.info('Eager mode check (streaming): eagerMode=$eagerMode, bufferNotEmpty=${responseBuffer.isNotEmpty}');
            if (eagerMode && responseBuffer.isNotEmpty) {
              _log.info('Triggering eager mode TTS for message: ${_messages[messageIndex].id}');
              // Wait a brief moment for UI to settle, then play streaming TTS
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && messageIndex != -1) {
                  // Use streaming TTS for eager mode (lower latency)
                  _log.info('Executing eager mode TTS playback');
                  _playStreamingTts(_messages[messageIndex]);
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
        final response = await FastApiService.sendMessage(
          messageText,
          conversationHistory: conversationContext,
          threadId: _currentThreadId,
          userId: _userId,
        );

        if (mounted) {
          // Check for errors
          if (response.containsKey('error')) {
            // Handle error
            setState(() {
              _messages.removeWhere((msg) => msg.id.startsWith('typing_'));
              _messages.add(ChatMessage(
                id: 'error_${DateTime.now().millisecondsSinceEpoch}',
                text: response['error'],
                isOwn: false,
                timestamp: DateTime.now(),
                author: 'System',
              ));
            });
            return;
          }

          // Update thread ID and message IDs
          _currentThreadId = response['thread_id'];

          // Update user message with backend message ID
          final userMsgIndex = _messages.indexWhere((msg) => msg.id == message.id);
          if (userMsgIndex != -1) {
            _messages[userMsgIndex].threadId = _currentThreadId;
            _messages[userMsgIndex].messageId = response['user_message_id'];
          }

          // Parse footnotes from the response
          final parsedResponse = _parseFootnotesFromResponse(response['response'] ?? '');

          // Create assistant message with parsed response and footnotes
          final assistantMessage = ChatMessage(
            id: 'assistant_${DateTime.now().millisecondsSinceEpoch}',
            text: parsedResponse.text,
            isOwn: false,
            timestamp: DateTime.now(),
            author: 'Assistant',
            footnotes: parsedResponse.footnotes,
            threadId: _currentThreadId,
            messageId: response['assistant_message_id'],
          );

          // Remove typing indicator and add complete response
          setState(() {
            _messages.removeWhere((msg) => msg.id.startsWith('typing_'));
            _messages.add(assistantMessage);
          });
          _scrollToBottom();

          // Add final response to conversation history
          final responseText = response['response'] ?? '';
          if (responseText.isNotEmpty) {
            _conversationHistory.add({
              'role': 'assistant',
              'content': responseText,
            });

            // Auto-trigger TTS if eager mode is enabled
            final eagerMode = ref.read(eagerModeProvider);
            _log.info('Eager mode check (non-streaming): eagerMode=$eagerMode');
            if (eagerMode) {
              _log.info('Triggering eager mode TTS for message: ${assistantMessage.id}');
              // Wait a brief moment for UI to settle, then play streaming TTS
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) {
                  _log.info('Executing eager mode TTS playback (non-streaming path)');
                  _playStreamingTts(assistantMessage);
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

  Future<void> _pickDocuments() async {
    final typeGroup = XTypeGroup(
      label: 'Documents',
      extensions: ['pdf', 'txt'],
    );

    final files = await openFiles(acceptedTypeGroups: [typeGroup]);

    if (files.isEmpty) return;

    for (final file in files) {
      final bytes = await file.readAsBytes();
      final size = bytes.length;

      // Validate size (10MB limit)
      if (size > 10 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${file.name} is too large (max 10MB)'),
              backgroundColor: Colors.red,
            ),
          );
        }
        continue;
      }

      ref.read(documentsProvider.notifier).addDocument(
        file.name,
        size,
        bytes,
      );
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

  /// Parse footnotes from text (alias for loading from history)
  _ParsedFootnoteResponse _parseFootnotesFromText(String text) {
    return _parseFootnotesFromResponse(text);
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
    final voiceShortcut = ref.watch(voiceShortcutProvider);

    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          voiceShortcut.logicalKey,
          alt: true,
        ): _toggleVoiceInput,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
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
                        IconButton(
                          onPressed: _createNewThread,
                          icon: const Icon(Icons.add),
                          tooltip: 'New conversation',
                        ),
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
        ),
      ),
    );
  }

  SidebarXTheme _buildSidebarTheme(BuildContext context) {
    final appColors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SidebarXTheme(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: isDark ? AppGradients.darkSidebarGradient : AppGradients.lightSidebarGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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
        gradient: isDark ? AppGradients.darkSidebarGradient : AppGradients.lightSidebarGradient,
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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
      SidebarXItem(
        icon: Icons.search,
        label: 'Search',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ChatHistoryPage(
                userId: _userId,
                onThreadSelected: _loadThreadConversation,
              ),
            ),
          );
        },
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

    Widget body;

    if (_showWelcomeScreen) {
      // Show welcome screen
      body = WelcomeHeroScreen(
        onGetStarted: () {
          setState(() {
            _showWelcomeScreen = false;
            _loadInitialMessages(); // Load welcome message after getting started
          });
          // Focus the message input
          _messageInputFocus.requestFocus();
        },
      );
    } else {
      // Show normal chat interface
      body = Column(
        children: [
          Expanded(
            child: _buildMessageList(),
          ),
          _buildMessageInput(),
        ],
      );
    }

    return GradientContainer(
      gradient: isDark
          ? AppGradients.darkBackgroundGradient
          : AppGradients.lightBackgroundGradient,
      child: Stack(
        children: [
          // Starfield effect (only in dark mode)
          if (isDark)
            Positioned.fill(
              child: ParticlesWidget(
                quantity: 120,
                ease: 80,
                color: const Color(0xFFFFE4B5), // Warm starlight color
                staticity: 50,
                size: 2.5,
              ),
            ),
          // Chat content on top
          body,
        ],
      ),
    );
  }

  Widget _buildAgentEndpointDisplay() {
    final appColors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get document count from provider
    final documents = ref.watch(documentsProvider);
    final docCount = documents.length;

    // Get the endpoint name
    final endpointName = _currentAgentEndpoint ?? 'Unknown';

    // Build display text
    final displayText = docCount > 0
        ? 'Agent Endpoint: $endpointName • $docCount doc${docCount > 1 ? 's' : ''}'
        : 'Agent Endpoint: $endpointName';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? appColors.messageBubble.withValues(alpha: 0.6)
            : appColors.muted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: docCount > 0
              ? appColors.accent.withValues(alpha: 0.5)
              : appColors.sidebarBorder.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            docCount > 0 ? Icons.description : Icons.smart_toy_outlined,
            size: 13,
            color: docCount > 0
                ? appColors.accent
                : appColors.sidebarPrimary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Text(
            displayText,
            style: TextStyle(
              fontSize: 10.5,
              color: appColors.messageText.withValues(alpha: 0.65),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
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
                              messageText: () {
                                final text = message.text == 'WELCOME_MESSAGE'
                                    ? (ref.isDarkMode ? 'Welcome to ${AppConstants.appNameDark}!' : 'Welcome to BrickChat!')
                                    : message.text;
                                // Debug: Log what's being passed to the widget
                                if (message.id.startsWith('loaded_')) {
                                  print('[DEBUG] Rendering loaded message: id=${message.id}, text_length=${text.length}, text_preview=${text.length > 50 ? text.substring(0, 50) : text}');
                                }
                                return text;
                              }(),
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
                // Sources accordion (only for assistant messages with citations)
                if (!message.isOwn && message.citations.isNotEmpty)
                  SourcesAccordion(
                    citations: message.citations,
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
                        // Streaming indicator with animated status text
                        if (message.isStreaming && !message.isOwn) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: AnimatedTextKit(
                              animatedTexts: [
                                TyperAnimatedText(
                                  'Working...',
                                  textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: appColors.accent,
                                    fontSize: 10,
                                  ),
                                  speed: const Duration(milliseconds: 80),
                                ),
                                TyperAnimatedText(
                                  'Contacting agent...',
                                  textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: appColors.accent,
                                    fontSize: 10,
                                  ),
                                  speed: const Duration(milliseconds: 60),
                                ),
                                TyperAnimatedText(
                                  'Gathering responses...',
                                  textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: appColors.accent,
                                    fontSize: 10,
                                  ),
                                  speed: const Duration(milliseconds: 50),
                                ),
                                TyperAnimatedText(
                                  'Resolving...',
                                  textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: appColors.accent,
                                    fontSize: 10,
                                  ),
                                  speed: const Duration(milliseconds: 70),
                                ),
                              ],
                              repeatForever: true,
                              pause: const Duration(milliseconds: 500),
                            ),
                          ),
                          const SizedBox(width: 4),
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
                            onTap: () async {
                              final newLikeState = message.isLiked == true ? null : true;
                              setState(() {
                                message.isLiked = newLikeState;
                              });
                              await _updateMessageFeedback(message, newLikeState);
                              _showFeedbackSnackBar(true, newLikeState == true);
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
                            onTap: () async {
                              final newLikeState = message.isLiked == false ? null : false;
                              setState(() {
                                message.isLiked = newLikeState;
                              });
                              await _updateMessageFeedback(message, newLikeState);
                              _showFeedbackSnackBar(false, newLikeState == false);
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
                                    _playStreamingTts(message);
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
                              // Download button (shown when audio is cached for this message)
                              if (_ttsAudioCache.containsKey(message.id)) ...[
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => _downloadTtsAudio(message.id),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: appColors.input.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      Icons.download,
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

          // Document chips (when files are staged/uploaded)
          Consumer(
            builder: (context, ref, _) {
              final documents = ref.watch(documentsProvider);
              if (documents.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: documents.map((doc) => DocumentChip(
                    filename: doc.filename,
                    size: doc.size,
                    isLoading: doc.isUploading,
                    onRemove: doc.isUploading ? null : () {
                      ref.read(documentsProvider.notifier).removeDocument(doc.filename);
                    },
                  )).toList(),
                ),
              );
            },
          ),

          // Agent endpoint display (always visible in bottom right)
          Align(
            alignment: Alignment.centerRight,
            child: _buildAgentEndpointDisplay(),
          ),
          const SizedBox(height: AppConstants.spacingSm),

          // Input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  focusNode: _messageInputFocus,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    prefixIcon: IconButton(
                      onPressed: _pickDocuments,
                      icon: Icon(
                        Icons.attach_file,
                        color: context.appColors.mutedForeground,
                      ),
                      tooltip: 'Attach document (PDF, TXT)',
                    ),
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
              Builder(
                builder: (context) {
                  final shortcut = ref.watch(voiceShortcutProvider);
                  return IconButton(
                    onPressed: _toggleVoiceInput,
                    icon: Icon(
                      _showSpeechToText ? Icons.keyboard : Icons.mic,
                      color: _showSpeechToText
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    ),
                    tooltip: _showSpeechToText
                        ? 'Hide voice input (${shortcut.displayName})'
                        : 'Voice input (${shortcut.displayName})',
                  );
                },
              ),

              const SizedBox(width: AppConstants.spacingXs),

              // Send button
              IconButton(
                onPressed: _sendMessage,
                icon: const Icon(Icons.send),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                tooltip: 'Send message',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Play TTS using streaming pipeline
  /// Streams audio chunks from backend and plays them with lowest latency
  void _playStreamingTts(ChatMessage message) async {
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

    // Set streaming state
    setState(() {
      _isStreamingTts = true;
      _isAudioLoading = true;
      _currentPlayingMessageId = message.id;
      _streamingNetworkDone = false; // Reset - network stream not yet complete
    });

    // Clear the audio queue
    _streamingAudioQueue.clear();

    try {
      _log.info('Starting streaming TTS for message: ${message.id}');

      // Get TTS voice setting (must be Deepgram voice for streaming)
      final ttsVoice = ref.read(ttsVoiceProvider);
      final streamingVoice = ttsVoice.startsWith('aura-') ? ttsVoice : 'aura-2-thalia-en';

      // Show streaming indicator
      if (mounted) {
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
                    'Streaming audio...',
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
            duration: Duration(seconds: 10),
            backgroundColor: Colors.blue.withValues(alpha: 0.85),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.snackBarRadius),
            ),
            elevation: 4,
            width: MediaQuery.of(context).size.width * AppConstants.snackBarWidthFactor,
          ),
        );
      }

      // Collect all audio chunks for sequential playback
      final allAudioBytes = <int>[];
      int sentencesProcessed = 0;

      await for (final event in FastApiService.streamTts(
        message.text,
        voice: streamingVoice,
      )) {
        if (!mounted || !_isStreamingTts) break;

        if (event['type'] == 'audio' && event['chunk'] != null) {
          final chunk = event['chunk'] as List<int>;
          allAudioBytes.addAll(chunk);
          _streamingAudioQueue.add(chunk);

          // Start playing as soon as we have the first chunk
          if (!_isPlayingFromQueue && _streamingAudioQueue.isNotEmpty) {
            setState(() {
              _isAudioLoading = false;
            });
            // Start playing the accumulated audio
            _playNextFromQueue();
          }
        } else if (event['type'] == 'done') {
          sentencesProcessed = event['sentences'] ?? 0;
          _log.info('Streaming TTS complete: $sentencesProcessed sentences');
          // Mark network streaming as complete - all chunks have been received
          _streamingNetworkDone = true;
        } else if (event['type'] == 'error') {
          _log.warning('Streaming TTS error: ${event['message']}');
          throw Exception(event['message']);
        }
      }

      // Cache the complete audio for download
      if (allAudioBytes.isNotEmpty) {
        _ttsAudioCache[message.id] = allAudioBytes;
      }

      // Clear snackbar and show success
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
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
                    'Playing audio ($sentencesProcessed sentences)',
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

    } catch (e) {
      _log.severe('Streaming TTS error: $e');
      if (mounted) {
        setState(() {
          _isStreamingTts = false;
          _isAudioLoading = false;
          _currentPlayingMessageId = null;
          _streamingNetworkDone = false;
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

  /// Play the next audio chunk from the streaming queue
  /// Each chunk is a complete MP3 file (one sentence), so they must be played separately
  void _playNextFromQueue() async {
    if (!mounted) return;

    if (_streamingAudioQueue.isEmpty) {
      // Queue empty - check if network streaming is also done
      if (_streamingNetworkDone) {
        // All done - clean up completely
        setState(() {
          _isPlayingFromQueue = false;
          _isAudioPlaying = false;
          _currentPlayingMessageId = null;
          _isStreamingTts = false;
        });
      } else {
        // Queue empty but network still streaming - wait for more chunks
        // DON'T set _isStreamingTts = false! The streaming loop will add more chunks.
        setState(() {
          _isPlayingFromQueue = false;
          _isAudioPlaying = false;
        });
      }
      return;
    }

    _isPlayingFromQueue = true;

    // Take just ONE chunk (one complete MP3 file per sentence)
    // DO NOT combine chunks - each is a separate MP3 with its own headers
    final audioBytes = _streamingAudioQueue.removeAt(0);

    if (audioBytes.isEmpty) {
      // Try next chunk
      _playNextFromQueue();
      return;
    }

    try {
      // Play single sentence audio
      await _playAudioBytesWeb(audioBytes);
    } catch (e) {
      _log.warning('Error playing audio chunk: $e');
      // Try to continue with next chunk on error
      _playNextFromQueue();
    }
  }

  /// Play audio bytes on web platform (helper for streaming)
  Future<void> _playAudioBytesWeb(List<int> audioBytes) async {
    if (!kIsWeb) return;

    // Convert bytes to base64
    final base64Audio = base64Encode(audioBytes);
    final dataUrl = 'data:audio/mpeg;base64,$base64Audio';

    // Create audio element
    final audio = Audio(dataUrl);

    // Set up ended handler to check for more chunks
    audio.onended = ((JSAny? event) {
      if (mounted) {
        // Check if there are more chunks to play
        if (_streamingAudioQueue.isNotEmpty) {
          _playNextFromQueue();
        } else if (_streamingNetworkDone) {
          // Network stream complete AND queue empty - we're done
          setState(() {
            _currentAudio = null;
            _currentPlayingMessageId = null;
            _isAudioPlaying = false;
            _isStreamingTts = false;
            _isPlayingFromQueue = false;
          });
        } else {
          // Queue empty but network still streaming - wait for more chunks
          // DON'T set _isStreamingTts = false here! That would break the streaming loop.
          setState(() {
            _isPlayingFromQueue = false;
            _isAudioPlaying = false;
          });
        }
      }
    }).toJS;

    audio.onerror = ((JSAny? error) {
      _log.warning('Streaming audio error: $error');
    }).toJS;

    // Store reference and play
    _currentAudio = audio;
    setState(() {
      _isAudioPlaying = true;
    });

    audio.load();
    await Future.delayed(Duration(milliseconds: 50));

    try {
      await audio.play().toDart;
    } catch (e) {
      _log.warning('Audio play error: $e');
      rethrow;
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
    }
    // Clear streaming state
    _streamingAudioQueue.clear();
    setState(() {
      _currentPlayingMessageId = null;
      _isAudioPlaying = false;
      _isAudioLoading = false;
      _isStreamingTts = false;
      _isPlayingFromQueue = false;
      _streamingNetworkDone = false;
    });
  }

  void _downloadTtsAudio(String messageId) {
    final audioBytes = _ttsAudioCache[messageId];
    if (audioBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No audio available to download',
            style: TextStyle(fontSize: 12, color: Colors.white),
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.orange.withValues(alpha: 0.85),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      // Convert bytes to base64 and create download link
      final base64Audio = base64Encode(audioBytes);
      final dataUrl = 'data:audio/mpeg;base64,$base64Audio';

      // Create timestamp for filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'tts_audio_$timestamp.mp3';

      // Use JS interop to trigger download
      _triggerDownload(dataUrl, filename);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_done,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Audio downloaded',
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
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green.withValues(alpha: 0.85),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.snackBarRadius),
          ),
          elevation: 4,
          width: MediaQuery.of(context).size.width * AppConstants.snackBarWidthFactor,
        ),
      );
    } catch (e) {
      _log.severe('Download error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to download audio: $e',
            style: TextStyle(fontSize: 12, color: Colors.white),
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red.withValues(alpha: 0.85),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _updateMessageFeedback(ChatMessage message, bool? isLiked) async {
    // Only update feedback if we have both thread ID and message ID
    if (_currentThreadId == null || message.messageId == null) {
      _log.warning('Cannot update feedback: missing thread or message ID');
      return;
    }

    String feedbackType = 'none';
    if (isLiked == true) {
      feedbackType = 'like';
    } else if (isLiked == false) {
      feedbackType = 'dislike';
    }

    try {
      final result = await FastApiService.updateFeedback(
        messageId: message.messageId!,
        threadId: _currentThreadId!,
        feedbackType: feedbackType,
        userId: _userId,
      );

      if (result.containsKey('error')) {
        _log.warning('Failed to update feedback: ${result['error']}');
      } else {
        _log.info('Feedback updated successfully');
      }
    } catch (e) {
      _log.warning('Error updating feedback: $e');
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

  /// Insert inline citation markers into text based on content_index
  /// Citations are grouped by content_index and appended as superscript numbers
  /// at the end of each paragraph/section
  String _insertCitationMarkers(String text, List<Map<String, dynamic>> citations) {
    if (citations.isEmpty) return text;

    // Group citations by content_index
    final Map<int, List<String>> citationsByIndex = {};
    for (final citation in citations) {
      final contentIndex = citation['content_index'] as int? ?? 0;
      final citationId = citation['id']?.toString() ?? '';
      if (citationId.isNotEmpty) {
        citationsByIndex.putIfAbsent(contentIndex, () => []);
        citationsByIndex[contentIndex]!.add(citationId);
      }
    }

    if (citationsByIndex.isEmpty) return text;

    // Split text into paragraphs (double newline or single newline followed by bullet/number)
    final paragraphPattern = RegExp(r'\n\n|\n(?=[-•*]|\d+\.)');
    final paragraphs = text.split(paragraphPattern);

    // If we have more content indices than paragraphs, try splitting by sentences for index 0
    // Otherwise, distribute citations across paragraphs
    if (paragraphs.length == 1 && citationsByIndex.length > 1) {
      // Single block of text - append all citations at the end
      final allCitations = citations.map((c) => c['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
      final markers = allCitations.map((id) => '[$id]').join('');
      return '$text $markers';
    }

    // Map content indices to paragraphs
    // content_index 0 = first paragraph, 1 = second, etc.
    final result = StringBuffer();
    for (int i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i];

      // Check if this paragraph index has citations
      if (citationsByIndex.containsKey(i)) {
        final markers = citationsByIndex[i]!.map((id) => '[$id]').join('');
        result.write(paragraph);
        // Add markers before the paragraph ends (before any trailing whitespace)
        final trimmed = paragraph.trimRight();
        if (trimmed != paragraph) {
          result.write(' $markers${paragraph.substring(trimmed.length)}');
        } else {
          result.write(' $markers');
        }
      } else {
        result.write(paragraph);
      }

      // Re-add paragraph separator (except for last)
      if (i < paragraphs.length - 1) {
        result.write('\n\n');
      }
    }

    // If there are citations for indices beyond our paragraph count, append them at the end
    final maxParagraphIndex = paragraphs.length - 1;
    final remainingCitations = <String>[];
    for (final entry in citationsByIndex.entries) {
      if (entry.key > maxParagraphIndex) {
        remainingCitations.addAll(entry.value);
      }
    }
    if (remainingCitations.isNotEmpty) {
      final markers = remainingCitations.map((id) => '[$id]').join('');
      result.write(' $markers');
    }

    return result.toString();
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
  List<Map<String, dynamic>> citations; // List of citations with title, url, content_index (mutable for streaming)
  String? threadId; // Thread ID from backend
  String? messageId; // Message ID from backend database
  String? agentEndpoint; // Agent/model endpoint used for this message

  ChatMessage({
    required this.id,
    required this.text,
    required this.isOwn,
    required this.timestamp,
    required this.author,
    this.threadId,
    this.messageId,
    this.agentEndpoint,
    this.isLiked,
    this.isStreaming = false,
    List<Map<String, String>>? footnotes,
    List<Map<String, dynamic>>? citations,
  }) : footnotes = footnotes ?? [],
       citations = citations ?? [];
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

// JS interop for file download using Blob (more reliable for binary data)
@JS('eval')
external JSFunction _jsEval(String code);

void _triggerDownload(String dataUrl, String filename) {
  // Use Blob URL approach for more reliable binary file downloads
  // This converts base64 back to binary and creates a proper Blob
  final script = '''
    (function(dataUrl, filename) {
      // Convert data URL to Blob
      var byteString = atob(dataUrl.split(',')[1]);
      var mimeType = dataUrl.split(',')[0].split(':')[1].split(';')[0];
      var ab = new ArrayBuffer(byteString.length);
      var ia = new Uint8Array(ab);
      for (var i = 0; i < byteString.length; i++) {
        ia[i] = byteString.charCodeAt(i);
      }
      var blob = new Blob([ab], {type: mimeType});

      // Create blob URL and trigger download
      var url = URL.createObjectURL(blob);
      var link = document.createElement('a');
      link.href = url;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);

      // Clean up blob URL after short delay
      setTimeout(function() { URL.revokeObjectURL(url); }, 100);
    })
  ''';
  final fn = _jsEval(script);
  fn.callAsFunction(null, dataUrl.toJS, filename.toJS);
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