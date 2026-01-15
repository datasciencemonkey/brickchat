"""Document storage and model API service for BrickChat"""
import os
import io
import json
import base64
import logging
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from pathlib import Path
from dotenv import load_dotenv
from openai import OpenAI
from databricks.sdk import WorkspaceClient

# Load environment variables before accessing them
load_dotenv()

logger = logging.getLogger(__name__)

# Configuration from environment
DOCUMENTS_VOLUME_PATH = os.environ.get('DOCUMENTS_VOLUME_PATH', './documents').rstrip('/')
DATABRICKS_BASE_URL = os.environ.get('DATABRICKS_BASE_URL', '')
DATABRICKS_DOCUMENT_MODEL = os.environ.get('DATABRICKS_DOCUMENT_MODEL', 'databricks-claude-sonnet-4-5')
DATABRICKS_TOKEN = os.environ.get('DATABRICKS_TOKEN', '')

# Extract Databricks host from base URL for SDK
# e.g., https://fevm-serverless-9cefok.cloud.databricks.com/serving-endpoints -> https://fevm-serverless-9cefok.cloud.databricks.com
DATABRICKS_HOST = '/'.join(DATABRICKS_BASE_URL.split('/')[:3]) if DATABRICKS_BASE_URL else ''

# Check if we're using a Unity Catalog volume path (starts with /Volumes/)
IS_VOLUME_PATH = DOCUMENTS_VOLUME_PATH.startswith('/Volumes/')

# Limits
MAX_FILES_PER_THREAD = 10
MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024  # 10MB
ALLOWED_EXTENSIONS = {'.pdf', '.txt'}


class DocumentService:
    """Handles document storage and model API integration"""

    def __init__(self):
        self._model_client = None
        self._workspace_client = None

    @property
    def model_client(self) -> OpenAI:
        """Lazy-load model client"""
        if self._model_client is None:
            self._model_client = OpenAI(
                api_key=DATABRICKS_TOKEN,
                base_url=DATABRICKS_BASE_URL
            )
        return self._model_client

    @property
    def workspace_client(self) -> WorkspaceClient:
        """Lazy-load Databricks WorkspaceClient for Unity Catalog volume operations"""
        if self._workspace_client is None:
            self._workspace_client = WorkspaceClient(
                host=DATABRICKS_HOST,
                token=DATABRICKS_TOKEN
            )
        return self._workspace_client

    def get_thread_documents_path(self, user_id: str, thread_id: str) -> str:
        """Get the path to a thread's document directory"""
        return f"{DOCUMENTS_VOLUME_PATH}/{user_id}/{thread_id}"

    def _get_file_path(self, user_id: str, thread_id: str, filename: str) -> str:
        """Get the full path to a specific file"""
        return f"{self.get_thread_documents_path(user_id, thread_id)}/{filename}"

    def _get_metadata_path(self, user_id: str, thread_id: str) -> str:
        """Get the path to the metadata.json file"""
        return f"{self.get_thread_documents_path(user_id, thread_id)}/metadata.json"

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
        """Save a document to the volume (Unity Catalog or local)"""
        # Check existing document count
        existing_docs = self.list_documents(user_id, thread_id)
        if len(existing_docs) >= MAX_FILES_PER_THREAD:
            raise ValueError(f"Maximum {MAX_FILES_PER_THREAD} documents per thread exceeded")

        file_path = self._get_file_path(user_id, thread_id, filename)

        if IS_VOLUME_PATH:
            # Use Databricks SDK to upload to Unity Catalog volume
            self.workspace_client.files.upload(
                file_path,
                io.BytesIO(content),
                overwrite=True
            )
            logger.info(f"Uploaded document {filename} to Unity Catalog volume: {file_path}")
        else:
            # Use local filesystem
            local_path = Path(file_path)
            local_path.parent.mkdir(parents=True, exist_ok=True)
            with open(local_path, 'wb') as f:
                f.write(content)
            logger.info(f"Saved document {filename} to local path: {file_path}")

        # Update metadata
        metadata = self._load_metadata(user_id, thread_id)
        metadata['documents'] = metadata.get('documents', {})
        metadata['documents'][filename] = {
            'size': len(content),
            'uploaded_at': datetime.utcnow().isoformat() + 'Z',
            'content_type': 'application/pdf' if filename.endswith('.pdf') else 'text/plain'
        }
        self._save_metadata(user_id, thread_id, metadata)

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
        file_path = self._get_file_path(user_id, thread_id, filename)

        try:
            if IS_VOLUME_PATH:
                # Use Databricks SDK to delete from Unity Catalog volume
                self.workspace_client.files.delete(file_path)
                logger.info(f"Deleted document {filename} from Unity Catalog volume: {file_path}")
            else:
                # Use local filesystem
                local_path = Path(file_path)
                if local_path.exists():
                    local_path.unlink()
                    logger.info(f"Deleted document {filename} from local path: {file_path}")
                else:
                    return False

            # Update metadata
            metadata = self._load_metadata(user_id, thread_id)
            if filename in metadata.get('documents', {}):
                del metadata['documents'][filename]
                self._save_metadata(user_id, thread_id, metadata)

            return True
        except Exception as e:
            logger.error(f"Failed to delete document {filename}: {e}")
            return False

    def thread_has_documents(self, user_id: str, thread_id: str) -> bool:
        """Check if a thread has any documents"""
        return len(self.list_documents(user_id, thread_id)) > 0

    def _read_file_content(self, file_path: str) -> Optional[bytes]:
        """Read file content from Unity Catalog volume or local filesystem"""
        try:
            if IS_VOLUME_PATH:
                # Use Databricks SDK to download from Unity Catalog volume
                response = self.workspace_client.files.download(file_path)
                return response.contents.read()
            else:
                # Use local filesystem
                local_path = Path(file_path)
                if local_path.exists():
                    with open(local_path, 'rb') as f:
                        return f.read()
                return None
        except Exception as e:
            logger.error(f"Failed to read file {file_path}: {e}")
            return None

    def load_documents_for_model(self, user_id: str, thread_id: str) -> List[Dict]:
        """Load documents formatted for model API"""
        documents = self.list_documents(user_id, thread_id)
        result = []

        for doc in documents:
            file_path = self._get_file_path(user_id, thread_id, doc['filename'])
            content = self._read_file_content(file_path)

            if content is not None:
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
        metadata_path = self._get_metadata_path(user_id, thread_id)
        content = self._read_file_content(metadata_path)
        if content is not None:
            try:
                return json.loads(content.decode('utf-8'))
            except json.JSONDecodeError:
                logger.error(f"Failed to parse metadata at {metadata_path}")
        return {}

    def _save_metadata(self, user_id: str, thread_id: str, metadata: Dict):
        """Save metadata.json for a thread"""
        metadata_path = self._get_metadata_path(user_id, thread_id)
        content = json.dumps(metadata, indent=2).encode('utf-8')

        if IS_VOLUME_PATH:
            # Use Databricks SDK to upload to Unity Catalog volume
            self.workspace_client.files.upload(
                metadata_path,
                io.BytesIO(content),
                overwrite=True
            )
        else:
            # Use local filesystem
            local_path = Path(metadata_path)
            local_path.parent.mkdir(parents=True, exist_ok=True)
            with open(local_path, 'w') as f:
                f.write(content.decode('utf-8'))


# Global instance
document_service = DocumentService()
