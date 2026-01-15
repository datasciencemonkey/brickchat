"""Document storage and model API service for BrickChat"""
import os
import io
import json
import base64
import logging
import asyncio
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from pathlib import Path
from dotenv import load_dotenv
from openai import OpenAI
from databricks.sdk import WorkspaceClient
from databricks import sql as databricks_sql

# Load environment variables before accessing them
load_dotenv()

# SQL Warehouse configuration
SQL_WAREHOUSE_HOSTNAME = os.environ.get('HOSTNAME', '').replace('https://', '')
SQL_WAREHOUSE_HTTP_PATH = os.environ.get('HTTP_PATH', '')

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

# Thread pool executor for async operations (Databricks SDK is synchronous)
_executor = ThreadPoolExecutor(max_workers=4)


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
                token=DATABRICKS_TOKEN,
                auth_type="pat"  # Force PAT to avoid conflict with auto-detected OAuth
            )
        return self._workspace_client

    @property
    def sql_connection(self):
        """Get Databricks SQL connection for fast file reads"""
        return databricks_sql.connect(
            server_hostname=SQL_WAREHOUSE_HOSTNAME,
            http_path=SQL_WAREHOUSE_HTTP_PATH,
            access_token=DATABRICKS_TOKEN
        )

    def get_thread_documents_path(self, user_id: str, thread_id: str) -> str:
        """Get the path to a thread's document directory"""
        return f"{DOCUMENTS_VOLUME_PATH}/{user_id}/{thread_id}"

    def _get_file_path(self, user_id: str, thread_id: str, filename: str) -> str:
        """Get the full path to a specific file"""
        return f"{self.get_thread_documents_path(user_id, thread_id)}/{filename}"

    def _get_metadata_path(self, user_id: str, thread_id: str) -> str:
        """Get the path to the metadata.json file"""
        return f"{self.get_thread_documents_path(user_id, thread_id)}/metadata.json"

    def _ensure_directory_exists(self, dir_path: str):
        """Create directory in Unity Catalog volume or local filesystem if it doesn't exist"""
        if IS_VOLUME_PATH:
            try:
                self.workspace_client.files.create_directory(dir_path)
                logger.info(f"Created directory: {dir_path}")
            except Exception as e:
                # Directory might already exist - that's OK (create_directory is idempotent)
                error_str = str(e).lower()
                if 'already exists' not in error_str and 'resource_already_exists' not in error_str:
                    logger.warning(f"Directory creation note for {dir_path}: {e}")
        else:
            Path(dir_path).mkdir(parents=True, exist_ok=True)

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

        # Ensure user/thread directory exists before upload
        thread_dir = self.get_thread_documents_path(user_id, thread_id)
        self._ensure_directory_exists(thread_dir)

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
        import time
        start = time.time()
        logger.info(f"[DOC_SVC] list_documents called for user={user_id}, thread={thread_id}")
        metadata = self._load_metadata(user_id, thread_id)
        elapsed = time.time() - start
        logger.info(f"[DOC_SVC] _load_metadata completed in {elapsed:.2f}s")
        docs = metadata.get('documents', {})
        logger.info(f"[DOC_SVC] Found {len(docs)} documents in metadata")
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
        logger.info(f"[DOC_SVC] thread_has_documents called for user={user_id}, thread={thread_id}")
        result = len(self.list_documents(user_id, thread_id)) > 0
        logger.info(f"[DOC_SVC] thread_has_documents returning {result}")
        return result

    def _read_file_content(self, file_path: str) -> Optional[bytes]:
        """Read file content from Unity Catalog volume or local filesystem"""
        import time
        logger.info(f"[DOC_SVC] _read_file_content called for {file_path}")
        try:
            if IS_VOLUME_PATH:
                # Check if file exists FIRST (fast check, avoids 5-minute timeout on download)
                logger.info(f"[DOC_SVC] Checking file metadata (existence check)...")
                start = time.time()
                try:
                    self.workspace_client.files.get_metadata(file_path)
                    elapsed = time.time() - start
                    logger.info(f"[DOC_SVC] File exists, metadata check took {elapsed:.2f}s")
                except Exception as e:
                    elapsed = time.time() - start
                    error_str = str(e).lower()
                    if 'not found' in error_str or '404' in str(e) or 'does not exist' in error_str:
                        logger.info(f"[DOC_SVC] File does not exist (checked in {elapsed:.2f}s): {file_path}")
                        return None  # Return immediately - no timeout
                    logger.error(f"[DOC_SVC] Metadata check error after {elapsed:.2f}s: {e}")
                    raise  # Re-raise other errors

                # File exists, now download it with timeout
                logger.info(f"[DOC_SVC] Downloading file...")
                start = time.time()

                # Use a timeout to prevent infinite blocking
                from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeoutError

                def do_download():
                    response = self.workspace_client.files.download(file_path)
                    return response.contents.read()

                try:
                    with ThreadPoolExecutor(max_workers=1) as download_executor:
                        future = download_executor.submit(do_download)
                        content = future.result(timeout=30)  # 30 second timeout
                    elapsed = time.time() - start
                    logger.info(f"[DOC_SVC] Download completed in {elapsed:.2f}s, size={len(content)}")
                    return content
                except FuturesTimeoutError:
                    elapsed = time.time() - start
                    logger.error(f"[DOC_SVC] Download TIMEOUT after {elapsed:.2f}s for {file_path}")
                    return None
            else:
                # Use local filesystem
                local_path = Path(file_path)
                if local_path.exists():
                    with open(local_path, 'rb') as f:
                        return f.read()
                return None
        except Exception as e:
            # Check if this is a "file not found" error (expected for new threads)
            error_str = str(e).lower()
            if 'not found' in error_str or 'nosuchkey' in error_str or 'does not exist' in error_str:
                logger.debug(f"File does not exist: {file_path}")
            else:
                logger.error(f"[DOC_SVC] Failed to read file {file_path}: {e}")
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

    def load_documents_via_sql(self, user_id: str, thread_id: str) -> List[Dict]:
        """
        Load documents using Databricks SQL READ_FILES() - much faster than SDK download.
        Returns documents formatted for LLM API.
        """
        import time
        start = time.time()
        thread_path = self.get_thread_documents_path(user_id, thread_id)
        logger.info(f"[DOC_SQL] Loading documents via SQL from {thread_path}")

        result = []

        try:
            with self.sql_connection as conn:
                with conn.cursor() as cursor:
                    # Query to find all files in the thread directory (excluding metadata.json)
                    # Using READ_FILES with binaryFile format returns base64-encoded content
                    query = f"""
                        SELECT
                            path,
                            content
                        FROM READ_FILES(
                            '{thread_path}/*',
                            format => 'binaryFile'
                        )
                        WHERE path NOT LIKE '%metadata.json'
                    """
                    cursor.execute(query)
                    rows = cursor.fetchall()

                    for row in rows:
                        file_path = row[0]
                        base64_content = row[1]
                        filename = file_path.split('/')[-1]

                        if filename.lower().endswith('.pdf'):
                            result.append({
                                'type': 'document',
                                'source': {
                                    'type': 'base64',
                                    'media_type': 'application/pdf',
                                    'data': base64_content
                                }
                            })
                        else:
                            # Decode base64 for text files
                            text_bytes = base64.b64decode(base64_content)
                            result.append({
                                'type': 'text',
                                'text': f"[Document: {filename}]\n\n{text_bytes.decode('utf-8')}"
                            })

                        logger.info(f"[DOC_SQL] Loaded {filename}")

            elapsed = time.time() - start
            logger.info(f"[DOC_SQL] Loaded {len(result)} documents in {elapsed:.2f}s")

        except Exception as e:
            elapsed = time.time() - start
            logger.error(f"[DOC_SQL] Error loading documents after {elapsed:.2f}s: {e}")
            # Fall back to empty - don't block the chat

        return result

    def format_document_for_llm(self, filename: str, content: bytes) -> Dict:
        """Format document bytes directly for LLM (no volume read needed)"""
        if filename.lower().endswith('.pdf'):
            return {
                'type': 'document',
                'source': {
                    'type': 'base64',
                    'media_type': 'application/pdf',
                    'data': base64.b64encode(content).decode('utf-8')
                }
            }
        else:  # .txt or other text files
            return {
                'type': 'text',
                'text': f"[Document: {filename}]\n\n{content.decode('utf-8')}"
            }

    async def save_documents_background(
        self,
        user_id: str,
        thread_id: str,
        files: List[Tuple[str, bytes]]
    ):
        """Save documents to volume in background (fire-and-forget)"""
        loop = asyncio.get_event_loop()
        for filename, content in files:
            try:
                await loop.run_in_executor(
                    _executor,
                    self.save_document,
                    user_id, thread_id, filename, content
                )
                logger.info(f"[BACKGROUND] Saved document to volume: {filename}")
            except Exception as e:
                logger.error(f"[BACKGROUND] Failed to save {filename}: {e}")

    def _load_metadata(self, user_id: str, thread_id: str) -> Dict:
        """Load metadata.json for a thread"""
        import time
        metadata_path = self._get_metadata_path(user_id, thread_id)
        logger.info(f"[DOC_SVC] _load_metadata reading from {metadata_path}")
        start = time.time()
        content = self._read_file_content(metadata_path)
        elapsed = time.time() - start
        logger.info(f"[DOC_SVC] _read_file_content completed in {elapsed:.2f}s, content_size={len(content) if content else 0}")
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

    # Async wrappers for FastAPI endpoints (Databricks SDK is synchronous)
    async def save_document_async(
        self,
        user_id: str,
        thread_id: str,
        filename: str,
        content: bytes
    ) -> Dict:
        """Async wrapper for save_document using run_in_executor"""
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            _executor,
            self.save_document,
            user_id,
            thread_id,
            filename,
            content
        )

    async def list_documents_async(self, user_id: str, thread_id: str) -> List[Dict]:
        """Async wrapper for list_documents"""
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            _executor,
            self.list_documents,
            user_id,
            thread_id
        )

    async def delete_document_async(self, user_id: str, thread_id: str, filename: str) -> bool:
        """Async wrapper for delete_document"""
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            _executor,
            self.delete_document,
            user_id,
            thread_id,
            filename
        )


# Global instance
document_service = DocumentService()
