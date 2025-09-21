import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';

class SpeechToTextWidget extends ConsumerStatefulWidget {
  final Function(String) onTextRecognized;
  final VoidCallback? onCancel;
  final String? hintText;
  final bool autoStart;

  const SpeechToTextWidget({
    super.key,
    required this.onTextRecognized,
    this.onCancel,
    this.hintText,
    this.autoStart = true,
  });

  @override
  ConsumerState<SpeechToTextWidget> createState() => _SpeechToTextWidgetState();
}

class _SpeechToTextWidgetState extends ConsumerState<SpeechToTextWidget>
    with TickerProviderStateMixin {
  late SpeechToText _speechToText;
  bool _speechEnabled = false;
  bool _isListening = false;
  String _recognizedText = '';
  String _errorMessage = '';
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _speechToText = SpeechToText();
    _focusNode = FocusNode();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _initSpeech();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _initSpeech() async {
    try {
      // Request microphone permission
      final microphoneStatus = await Permission.microphone.request();

      if (microphoneStatus.isGranted) {
        _speechEnabled = await _speechToText.initialize(
          onError: (error) {
            if (mounted) {
              setState(() {
                _errorMessage = error.errorMsg;
                _isListening = false;
              });
              _stopAnimations();
            }
          },
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              if (mounted) {
                setState(() {
                  _isListening = false;
                });
                _stopAnimations();
              }
            }
          },
        );

        // Auto-start listening if enabled and speech is available
        if (_speechEnabled && widget.autoStart && mounted) {
          // Add a small delay to ensure the widget is fully built
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted && !_isListening) {
            _startListening();
            // Request focus to capture keyboard events
            _focusNode.requestFocus();
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Microphone permission denied';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize speech recognition: $e';
        });
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _startListening() async {
    if (!_speechEnabled) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Speech recognition not available';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isListening = true;
        _recognizedText = '';
        _errorMessage = '';
      });
    }

    _startAnimations();

    try {
      await _speechToText.listen(
        onResult: (result) {
          if (mounted) {
            setState(() {
              _recognizedText = result.recognizedWords;
            });

            if (result.finalResult) {
              widget.onTextRecognized(_recognizedText);
              _stopListening();
            }
          }
        },
        localeId: 'en_US',
        listenFor: const Duration(seconds: 120),
        pauseFor: const Duration(seconds: 3),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to start listening: $e';
          _isListening = false;
        });
        _stopAnimations();
      }
    }
  }

  void _stopListening() async {
    await _speechToText.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
      _stopAnimations();
    }
  }

  void _cancelListening() async {
    await _speechToText.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
        _recognizedText = '';
        _errorMessage = '';
      });
      _stopAnimations();
    }
    widget.onCancel?.call();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelListening();
      return true;
    }
    return false;
  }

  void _startAnimations() {
    _pulseController.repeat(reverse: true);
    _waveController.repeat();
  }

  void _stopAnimations() {
    _pulseController.stop();
    _waveController.stop();
    _pulseController.reset();
    _waveController.reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final extension = theme.extension<AppColorsExtension>()!;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isListening ? colorScheme.primary : extension.input,
            width: _isListening ? 2 : 1,
          ),
          boxShadow: _isListening
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Status text
          Text(
            _errorMessage.isNotEmpty
                ? _errorMessage
                : _isListening
                    ? 'Listening... (Press Esc to cancel)'
                    : _speechEnabled
                        ? widget.hintText ?? 'Tap to speak'
                        : 'Initializing speech recognition...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _errorMessage.isNotEmpty
                  ? colorScheme.error
                  : _isListening
                      ? colorScheme.primary
                      : extension.mutedForeground,
            ),
          ),

          const SizedBox(height: 16),

          // Microphone button with animations
          GestureDetector(
            onTap: _speechEnabled
                ? (_isListening ? _stopListening : _startListening)
                : null,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _isListening
                    ? colorScheme.primary
                    : _speechEnabled
                        ? colorScheme.primaryContainer
                        : extension.muted,
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ripple effect when listening
                  if (_isListening)
                    AnimatedBuilder(
                      animation: _waveController,
                      builder: (context, child) {
                        return Container(
                          width: 80 + (40 * _waveController.value),
                          height: 80 + (40 * _waveController.value),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.primary.withValues(
                                alpha: 0.3 * (1 - _waveController.value),
                              ),
                              width: 2,
                            ),
                          ),
                        );
                      },
                    ),

                  // Pulse effect
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isListening ? (1.0 + (0.1 * _pulseController.value)) : 1.0,
                        child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          size: 36,
                          color: _isListening
                              ? colorScheme.onPrimary
                              : _speechEnabled
                                  ? colorScheme.onPrimaryContainer
                                  : extension.mutedForeground,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ).animate(target: _isListening ? 1 : 0).scaleXY(
              begin: 1.0,
              end: 1.05,
              duration: 200.ms,
              curve: Curves.easeInOut,
            ),
          ),

          const SizedBox(height: 16),

          // Recognized text or error
          if (_recognizedText.isNotEmpty || _errorMessage.isNotEmpty)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                minHeight: 72, // Accommodate 3-4 lines of text
                maxHeight: 96,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _errorMessage.isNotEmpty
                    ? colorScheme.errorContainer
                    : extension.input,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _errorMessage.isNotEmpty ? _errorMessage : _recognizedText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _errorMessage.isNotEmpty
                        ? colorScheme.onErrorContainer
                        : colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }
}