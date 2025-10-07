# Welcome to BrickChat! 🧱💬

**BrickChat** is a sophisticated AI-powered chat application designed specifically for interacting with Databricks AI agents. Built with Flutter and featuring a modern, professional interface, it offers a seamless conversational experience across web and desktop platforms.

## ✨ Key Features

### 🎯 **AI-Powered Conversations**
- **Databricks Integration**: Direct connection to Databricks serving endpoints for intelligent responses
- **Context-Aware Chat**: Maintains conversation history with smart context management
- **Dual Response Modes**: Choose between streaming (word-by-word) or instant complete responses
- **Multi-turn Conversations**: Full conversation context preserved for coherent interactions

### 🎤 **Voice Interaction**
- **Speech-to-Text**: Click the microphone to speak your messages naturally
- **Real-time Recognition**: Live transcription with visual feedback and animations
- **Permission Handling**: Seamless microphone access with user-friendly prompts
- **Keyboard Shortcuts**: Press Escape to cancel voice input

### 🔊 **Text-to-Speech (TTS) Features**
- **Dual Provider Support**: Choose between Replicate (Kokoro-82M) or Deepgram (Aura) for optimal voice quality
- **18+ Voice Options**: Select from diverse voices including male and female options
- **AI-Powered Text Cleaning**: LLM intelligently removes footnotes, HTML tags, and formatting for natural speech
- **Smart Caching**: LRU cache stores 100 cleaned texts to reduce API calls and improve response time
- **Streaming TTS**: Real-time audio playback as responses are generated (when streaming enabled)
- **Eager Mode**: Automatically play TTS after AI responses (works with both streaming and non-streaming modes)
- **Manual TTS Control**: Click the speaker icon on any message to play audio
- **Provider Fallback**: Automatic fallback between TTS providers if one fails
- **Voice Persistence**: Your voice and provider preferences are saved across sessions

### 🎨 **Beautiful, Adaptive Interface**
- **Dual Themes**: Switch between light ("BrickChat") and dark ("**Customer**Chat") modes with smooth transitions
- **Professional Design**: Clean, minimalistic interface with Databricks brand colors
- **Responsive Layout**: Optimized for web browsers and desktop applications
- **Animated Elements**: Smooth transitions, typing indicators, and visual feedback

### 💬 **Rich Messaging Experience**
- **Markdown Support**: Format messages with bold, italic, code blocks, links, and footnotes
- **Message Actions**: Like/dislike, copy to clipboard, and text-to-speech playback
- **Typing Indicators**: Animated "Assistant is working..." with engaging status messages
- **Message History**: Scrollable conversation with timestamps and author labels
- **Collapsible Reasoning**: AI reasoning displayed in expandable sections for transparency
- **Footnotes Support**: Interactive footnotes with hover tooltips and expandable content

### ⚙️ **Customizable Settings**
- **Streaming Toggle**: Enable/disable real-time response streaming (experimental)
- **Eager Mode**: Automatically play text-to-speech (works with or without streaming)
- **TTS Provider Selection**: Choose between Replicate (Kokoro-82M) or Deepgram (Aura) voices
- **Voice Customization**: Select from 18+ voices across different providers
- **Theme Persistence**: Your theme preference is remembered across sessions
- **Settings Panel**: Easy access to app configuration and information

### 🔧 **Technical Excellence**
- **Cross-Platform**: Works across iOS, Android, Web browsers, and Desktop (Windows, macOS, Linux)
- **WASM Compatible**: Modern web technology for optimal performance
- **Clean Architecture**: Built with Flutter and Riverpod for maintainable code
- **LLM-Enhanced TTS**: Backend uses Databricks LLM to intelligently clean text for optimal speech output
- **Efficient Caching**: LRU cache reduces API calls while maintaining fresh, context-aware text processing
- **Error Handling**: Graceful error management with user-friendly messages

## 🎯 **Perfect For**
- **Data Scientists** working with Databricks platforms
- **AI Researchers** needing intelligent conversation tools
- **Business Users** requiring professional chat interfaces
- **Developers** building AI-powered applications

## ⚙️ **Response Modes & TTS Settings**

### **Streaming and Eager Mode**
BrickChat offers flexible response modes that can work independently or together:

- **Streaming Mode** (Experimental): Responses appear word-by-word as they are generated, providing real-time feedback
- **Eager Mode**: Automatically plays text-to-speech:
  - When streaming is enabled: TTS plays after the streaming response completes
  - When streaming is disabled: TTS plays after the full response is received

Both modes can now be enabled simultaneously for the ultimate interactive experience!

### **TTS Configuration**
Access the settings panel to customize your text-to-speech experience:

1. **Provider Selection**: Choose between Replicate (Kokoro-82M) or Deepgram (Aura)
2. **Voice Selection**: Pick from 18+ voices including male and female options
3. **Eager Mode**: Enable automatic TTS playback after responses complete
4. **Manual Control**: Click the speaker icon on any message for on-demand audio

### **AI-Powered TTS Processing**
BrickChat uses advanced LLM technology to ensure optimal text-to-speech output:

- **Intelligent Text Cleaning**: Backend LLM automatically removes footnotes, HTML tags, and formatting artifacts
- **Context-Aware Processing**: The AI understands context and preserves meaning while optimizing for natural speech
- **Efficient Caching**: LRU cache with 100-item capacity reduces API calls for frequently spoken content
- **Seamless Integration**: All processing happens server-side - no client-side complexity

## 🚀 **Getting Started**
Simply type your message or click the microphone to start speaking. The AI assistant will respond intelligently based on your conversation context, making it feel like chatting with a knowledgeable colleague.

**Built with ❤️ using Flutter, Databricks, and modern web technologies.**