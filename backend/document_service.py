"""Document storage and Claude API service for BrickChat"""
import os
import json
import base64
import logging
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from pathlib import Path
from openai import OpenAI

logger = logging.getLogger(__name__)

# Configuration from environment
DOCUMENTS_VOLUME_PATH = os.environ.get('DOCUMENTS_VOLUME_PATH', './documents')
DATABRICKS_BASE_URL = os.environ.get('DATABRICKS_BASE_URL', '')
DATABRICKS_DOCUMENT_MODEL = os.environ.get('DATABRICKS_DOCUMENT_MODEL', 'claude-opus-4-5')
DATABRICKS_TOKEN = os.environ.get('DATABRICKS_TOKEN', '')

# Export for backward compatibility
CLAUDE_MODEL = DATABRICKS_DOCUMENT_MODEL

# Limits
MAX_FILES_PER_THREAD = 10
MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024  # 10MB
ALLOWED_EXTENSIONS = {'.pdf', '.txt'}


class DocumentService:
    """Handles document storage and Claude API integration"""

    def __init__(self):
        self._claude_client = None

    @property
    def claude_client(self) -> OpenAI:
        """Lazy-load Claude client"""
        if self._claude_client is None:
            self._claude_client = OpenAI(
                api_key=DATABRICKS_TOKEN,
                base_url=DATABRICKS_BASE_URL
            )
        return self._claude_client

    def get_thread_documents_path(self, user_id: str, thread_id: str) -> Path:
        """Get the path to a thread's document directory"""
        return Path(DOCUMENTS_VOLUME_PATH) / user_id / thread_id

    def validate_file(self, filename: str, size: int) -> Tuple[bool, str]:
        """Validate file against limits"""
        ext = Path(filename).suffix.lower()
        if ext not in ALLOWED_EXTENSIONS:
            return False, f"File type '{ext}' not allowed. Allowed: {', '.join(ALLOWED_EXTENSIONS)}"
        if size > MAX_FILE_SIZE_BYTES:
            return False, f"File too large ({size} bytes). Max: {MAX_FILE_SIZE_BYTES} bytes"
        return True, ""

    def save_document(
        self,
        user_id: str,
        thread_id: str,
        filename: str,
        content: bytes
    ) -> Dict:
        """Save a document to the volume"""
        doc_path = self.get_thread_documents_path(user_id, thread_id)
        doc_path.mkdir(parents=True, exist_ok=True)

        # Check existing document count
        existing_docs = self.list_documents(user_id, thread_id)
        if len(existing_docs) >= MAX_FILES_PER_THREAD:
            raise ValueError(f"Maximum {MAX_FILES_PER_THREAD} documents per thread exceeded")

        # Save the file
        file_path = doc_path / filename
        with open(file_path, 'wb') as f:
            f.write(content)

        # Update metadata
        metadata = self._load_metadata(user_id, thread_id)
        metadata['documents'] = metadata.get('documents', {})
        metadata['documents'][filename] = {
            'size': len(content),
            'uploaded_at': datetime.utcnow().isoformat() + 'Z',
            'content_type': 'application/pdf' if filename.endswith('.pdf') else 'text/plain'
        }
        self._save_metadata(user_id, thread_id, metadata)

        logger.info(f"Saved document {filename} for user {user_id}, thread {thread_id}")
        return {
            'filename': filename,
            'size': len(content),
            'status': 'uploaded'
        }

    def list_documents(self, user_id: str, thread_id: str) -> List[Dict]:
        """List all documents for a thread"""
        metadata = self._load_metadata(user_id, thread_id)
        docs = metadata.get('documents', {})
        return [
            {
                'filename': fname,
                'size': info.get('size', 0),
                'uploaded_at': info.get('uploaded_at', ''),
                'content_type': info.get('content_type', 'application/octet-stream')
            }
            for fname, info in docs.items()
        ]

    def delete_document(self, user_id: str, thread_id: str, filename: str) -> bool:
        """Delete a document from a thread"""
        doc_path = self.get_thread_documents_path(user_id, thread_id)
        file_path = doc_path / filename

        if file_path.exists():
            file_path.unlink()

            # Update metadata
            metadata = self._load_metadata(user_id, thread_id)
            if filename in metadata.get('documents', {}):
                del metadata['documents'][filename]
                self._save_metadata(user_id, thread_id, metadata)

            logger.info(f"Deleted document {filename} for user {user_id}, thread {thread_id}")
            return True
        return False

    def thread_has_documents(self, user_id: str, thread_id: str) -> bool:
        """Check if a thread has any documents"""
        return len(self.list_documents(user_id, thread_id)) > 0

    def load_documents_for_claude(self, user_id: str, thread_id: str) -> List[Dict]:
        """Load documents formatted for Claude API"""
        doc_path = self.get_thread_documents_path(user_id, thread_id)
        documents = self.list_documents(user_id, thread_id)
        result = []

        for doc in documents:
            file_path = doc_path / doc['filename']
            if file_path.exists():
                with open(file_path, 'rb') as f:
                    content = f.read()

                if doc['filename'].endswith('.pdf'):
                    # PDF: send as base64-encoded file
                    result.append({
                        'type': 'document',
                        'source': {
                            'type': 'base64',
                            'media_type': 'application/pdf',
                            'data': base64.b64encode(content).decode('utf-8')
                        }
                    })
                else:
                    # TXT: send as plain text
                    result.append({
                        'type': 'text',
                        'text': f"[Document: {doc['filename']}]\n\n{content.decode('utf-8')}"
                    })

        return result

    def _load_metadata(self, user_id: str, thread_id: str) -> Dict:
        """Load metadata.json for a thread"""
        metadata_path = self.get_thread_documents_path(user_id, thread_id) / 'metadata.json'
        if metadata_path.exists():
            with open(metadata_path, 'r') as f:
                return json.load(f)
        return {}

    def _save_metadata(self, user_id: str, thread_id: str, metadata: Dict):
        """Save metadata.json for a thread"""
        doc_path = self.get_thread_documents_path(user_id, thread_id)
        doc_path.mkdir(parents=True, exist_ok=True)
        metadata_path = doc_path / 'metadata.json'
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2)


# Global instance
document_service = DocumentService()
