import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// A chip widget representing an uploaded document with remove functionality
class DocumentChip extends StatelessWidget {
  final String filename;
  final int? size;
  final bool isLoading;
  final VoidCallback? onRemove;

  const DocumentChip({
    super.key,
    required this.filename,
    this.size,
    this.isLoading = false,
    this.onRemove,
  });

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon() {
    if (filename.toLowerCase().endsWith('.pdf')) {
      return Icons.picture_as_pdf;
    } else if (filename.toLowerCase().endsWith('.txt')) {
      return Icons.description;
    }
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? appColors.messageBubble.withValues(alpha: 0.6)
            : appColors.muted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: appColors.sidebarBorder.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // File icon
          Icon(
            _getFileIcon(),
            size: 16,
            color: appColors.accent,
          ),
          const SizedBox(width: 6),

          // Filename and size
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  filename,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: appColors.messageText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (size != null)
                  Text(
                    _formatFileSize(size!),
                    style: TextStyle(
                      fontSize: 10,
                      color: appColors.mutedForeground,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          // Loading indicator or remove button
          if (isLoading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: appColors.accent,
              ),
            )
          else if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: appColors.mutedForeground.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: appColors.mutedForeground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
