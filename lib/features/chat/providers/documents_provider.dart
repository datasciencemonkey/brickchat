import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents a document staged for upload or already uploaded
class StagedDocument {
  final String filename;
  final int size;
  final List<int>? bytes; // Raw bytes for upload (null if already uploaded)
  final bool isUploading;
  final String? uploadedAt;

  StagedDocument({
    required this.filename,
    required this.size,
    this.bytes,
    this.isUploading = false,
    this.uploadedAt,
  });

  bool get isUploaded => uploadedAt != null;

  StagedDocument copyWith({
    String? filename,
    int? size,
    List<int>? bytes,
    bool? isUploading,
    String? uploadedAt,
  }) {
    return StagedDocument(
      filename: filename ?? this.filename,
      size: size ?? this.size,
      bytes: bytes ?? this.bytes,
      isUploading: isUploading ?? this.isUploading,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }
}

/// State notifier for managing staged and uploaded documents
class DocumentsNotifier extends StateNotifier<List<StagedDocument>> {
  DocumentsNotifier() : super([]);

  /// Add a new document to the staged list
  void addDocument(String filename, int size, List<int> bytes) {
    // Check if document with same name already exists
    if (state.any((doc) => doc.filename == filename)) {
      return; // Don't add duplicates
    }
    state = [...state, StagedDocument(filename: filename, size: size, bytes: bytes)];
  }

  /// Remove a document by filename
  void removeDocument(String filename) {
    state = state.where((doc) => doc.filename != filename).toList();
  }

  /// Mark a document as uploading
  void setUploading(String filename, bool isUploading) {
    state = state.map((doc) {
      if (doc.filename == filename) {
        return doc.copyWith(isUploading: isUploading);
      }
      return doc;
    }).toList();
  }

  /// Mark a document as uploaded
  void markUploaded(String filename, String uploadedAt) {
    state = state.map((doc) {
      if (doc.filename == filename) {
        return doc.copyWith(isUploading: false, uploadedAt: uploadedAt, bytes: null);
      }
      return doc;
    }).toList();
  }

  /// Load documents from backend response (for thread reload)
  void loadFromBackend(List<Map<String, dynamic>> documents) {
    state = documents.map((doc) => StagedDocument(
      filename: doc['filename'] ?? '',
      size: doc['size'] ?? 0,
      uploadedAt: doc['uploaded_at'],
    )).toList();
  }

  /// Clear all documents (for new conversation)
  void clear() {
    state = [];
  }

  /// Get documents that need to be uploaded
  List<StagedDocument> get pendingUploads =>
      state.where((doc) => !doc.isUploaded && !doc.isUploading).toList();

  /// Check if any documents are present
  bool get hasDocuments => state.isNotEmpty;

  /// Get total size of all documents
  int get totalSize => state.fold(0, (sum, doc) => sum + doc.size);
}

/// Provider for documents state
final documentsProvider =
    StateNotifierProvider<DocumentsNotifier, List<StagedDocument>>((ref) {
  return DocumentsNotifier();
});

/// Computed provider: whether documents are present (for endpoint switching)
final hasDocumentsProvider = Provider<bool>((ref) {
  final documents = ref.watch(documentsProvider);
  return documents.isNotEmpty;
});

/// Computed provider: current endpoint based on document presence
final activeEndpointProvider = Provider<String?>((ref) {
  final hasDocuments = ref.watch(hasDocumentsProvider);
  // Return Claude model name when documents present, null otherwise (use default)
  return hasDocuments ? 'claude-opus-4-5' : null;
});
