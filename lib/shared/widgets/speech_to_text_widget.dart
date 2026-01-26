import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:glowy_borders/glowy_borders.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

class SpeechToTextWidget extends ConsumerStatefulWidget {
  final Function(String) onTextRecognized;
  final VoidCallback? onCancel;
  /// Called when user manually submits recognized text via the submit button
  final Function(String)? onSubmit;
  /// Called when user dismisses voice mode (Escape) with partial text to populate input field
  final Function(String)? onDismissWithText;
  final String? hintText;
  final bool autoStart;

  const SpeechToTextWidget({
    super.key,
    required this.onTextRecognized,
    this.onCancel,
    this.onSubmit,
    this.onDismissWithText,
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
      duration: AppConstants.speechPulseAnimation,
      vsync: this,
    );
    _waveController = AnimationController(
      duration: AppConstants.speechWaveAnimation,
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
          await Future.delayed(AppConstants.speechInitDelay);
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
        listenFor: AppConstants.speechListenDuration,
        pauseFor: AppConstants.speechPauseDuration,
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
    final textToPassBack = _recognizedText;
    await _speechToText.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
        _recognizedText = '';
        _errorMessage = '';
      });
      _stopAnimations();
    }
    // Pass any captured text back to populate the input field
    if (textToPassBack.isNotEmpty) {
      widget.onDismissWithText?.call(textToPassBack);
    }
    widget.onCancel?.call();
  }

  /// Manually submit the current recognized text
  void _submitText() async {
    if (_recognizedText.isEmpty) return;

    final textToSubmit = _recognizedText;
    await _speechToText.stop();

    if (mounted) {
      setState(() {
        _isListening = false;
        _recognizedText = '';
        _errorMessage = '';
      });
      _stopAnimations();
    }

    // Use onSubmit if provided, otherwise fall back to onTextRecognized
    if (widget.onSubmit != null) {
      widget.onSubmit!(textToSubmit);
    } else {
      widget.onTextRecognized(textToSubmit);
    }
    widget.onCancel?.call();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelListening();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter && _recognizedText.isNotEmpty) {
        _submitText();
        return true;
      }
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

  List<Color> _buildGlowColors() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final extension = theme.extension<AppColorsExtension>()!;
    final isDark = theme.brightness == Brightness.dark;

    if (_isListening) {
      // More vibrant glow when listening
      if (isDark) {
        return [
          colorScheme.primary.withValues(alpha: 0.8),
          extension.accent.withValues(alpha: 0.6),
          Colors.blue.withValues(alpha: 0.7),
          colorScheme.primary.withValues(alpha: 0.5),
        ];
      } else {
        return [
          colorScheme.primary.withValues(alpha: 0.7),
          Colors.blue[400]!.withValues(alpha: 0.6),
          extension.accent.withValues(alpha: 0.5),
          colorScheme.primary.withValues(alpha: 0.4),
        ];
      }
    } else {
      // Subtle glow when not listening
      if (isDark) {
        return [
          extension.accent.withValues(alpha: 0.3),
          extension.mutedForeground.withValues(alpha: 0.2),
          Colors.blue.withValues(alpha: 0.2),
          extension.accent.withValues(alpha: 0.1),
        ];
      } else {
        return [
          extension.accent.withValues(alpha: 0.2),
          Colors.blue[300]!.withValues(alpha: 0.2),
          extension.mutedForeground.withValues(alpha: 0.1),
          extension.accent.withValues(alpha: 0.1),
        ];
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final extension = theme.extension<AppColorsExtension>()!;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: AnimatedGradientBorder(
        borderSize: AppConstants.glowBorderSize,
        glowSize: _isListening ? AppConstants.speechGlowSizeListening : AppConstants.speechGlowSizeIdle,
        borderRadius: BorderRadius.circular(AppConstants.speechRadius),
        gradientColors: _buildGlowColors(),
        animationProgress: null, // null = infinite animation
        child: Container(
          padding: AppConstants.speechContainerPadding,
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(AppConstants.speechRadius),
          ),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Status text
          Text(
            _errorMessage.isNotEmpty
                ? _errorMessage
                : _isListening
                    ? 'Listening... (Enter to send, Esc to cancel)'
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

          SizedBox(height: AppConstants.spacingMd),

          // Microphone and Submit buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Microphone button with animations
              GestureDetector(
                onTap: _speechEnabled
                    ? (_isListening ? _stopListening : _startListening)
                    : null,
                child: Container(
                  width: AppConstants.speechMicrophoneSize,
                  height: AppConstants.speechMicrophoneSize,
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
                              width: AppConstants.speechMicrophoneSize + (AppConstants.speechWaveExpansion * _waveController.value),
                              height: AppConstants.speechMicrophoneSize + (AppConstants.speechWaveExpansion * _waveController.value),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.3 * (1 - _waveController.value),
                                  ),
                                  width: AppConstants.speechWaveBorderWidth,
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
                              size: AppConstants.speechMicrophoneIconSize,
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

              const SizedBox(width: 16),

              // Submit button - enabled when text is recognized
              AnimatedOpacity(
                opacity: _recognizedText.isNotEmpty ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: _recognizedText.isNotEmpty ? _submitText : null,
                  child: Container(
                    width: AppConstants.speechMicrophoneSize,
                    height: AppConstants.speechMicrophoneSize,
                    decoration: BoxDecoration(
                      color: _recognizedText.isNotEmpty
                          ? colorScheme.primary
                          : extension.muted,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send,
                      size: AppConstants.speechMicrophoneIconSize,
                      color: _recognizedText.isNotEmpty
                          ? colorScheme.onPrimary
                          : extension.mutedForeground,
                    ),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: AppConstants.spacingMd),

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
      ),
    );
  }
}