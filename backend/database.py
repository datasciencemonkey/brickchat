"""Database connection and utilities for BrickChat feedback system"""
import os
from typing import Dict, List, Optional
from psycopg2.extras import RealDictCursor, Json
from psycopg2.pool import SimpleConnectionPool
import logging

logger = logging.getLogger(__name__)


def normalize_unicode(text: Optional[str]) -> str:
    """
    Normalize Unicode ligatures and special characters.
    Applied at write-time to avoid repeated processing on reads.

    Handles:
    - \ufb01 (fi ligature) -> 'fi'
    - \ufb02 (fl ligature) -> 'fl'
    - \u25cf (black circle) -> '•' (bullet)
    """
    if not text:
        return ''
    return (text
        .replace('\ufb01', 'fi')
        .replace('\ufb02', 'fl')
        .replace('\u25cf', '•'))

class DatabaseManager:
    """Manages PostgreSQL database connections and operations"""

    def __init__(self):
        self.pool = None
        self._initialize_pool()

    def _initialize_pool(self):
        """Initialize connection pool"""
        try:
            # Get connection parameters from environment variables
            self.pool = SimpleConnectionPool(
                1, 20,  # min and max connections
                host=os.getenv('PGHOST', ''),
                database=os.getenv('PGDATABASE', 'brickchat'),
                user=os.getenv('PGUSER', 'service_brickchat'),
                password=os.getenv('PG_PASS', ''),
                port=os.getenv('PGPORT', '5432'),
                sslmode='require' if 'databricks' in os.getenv('PGHOST', '') else 'prefer'
            )
            logger.info("Database connection pool initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize database pool: {e}")
            raise

    def get_connection(self):
        """Get a connection from the pool"""
        conn = self.pool.getconn()
        # Test if connection is alive
        try:
            with conn.cursor() as cursor:
                cursor.execute("SELECT 1")
        except Exception:
            # Connection is dead, recreate it
            self.pool.putconn(conn, close=True)
            conn = self.pool.getconn()
        return conn

    def put_connection(self, conn):
        """Return a connection to the pool"""
        self.pool.putconn(conn)

    def execute_query(self, query: str, params: tuple = None, fetch: bool = True):
        """Execute a query and optionally fetch results"""
        conn = None
        try:
            conn = self.get_connection()
            with conn.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute(query, params)
                conn.commit()
                if fetch:
                    return cursor.fetchall()
                return cursor.rowcount
        except Exception as e:
            if conn:
                conn.rollback()
            logger.error(f"Query execution failed: {e}")
            raise
        finally:
            if conn:
                self.put_connection(conn)

    def execute_query_one(self, query: str, params: tuple = None):
        """Execute a query and fetch one result"""
        conn = None
        try:
            conn = self.get_connection()
            with conn.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute(query, params)
                conn.commit()
                return cursor.fetchone()
        except Exception as e:
            if conn:
                conn.rollback()
            logger.error(f"Query execution failed: {e}")
            raise
        finally:
            if conn:
                self.put_connection(conn)

class ChatDatabase:
    """Handles chat-specific database operations"""

    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager

    def get_user_threads_with_last_message(self, user_id: str) -> List[Dict]:
        """Get all threads for a user with their last message"""
        query = """
            SELECT
                t.thread_id,
                t.created_at as thread_created_at,
                t.updated_at as thread_updated_at,
                m.message_content as last_message,
                m.created_at as last_message_time,
                m.message_role as last_message_role,
                m.agent_endpoint as agent_endpoint,
                (
                    SELECT message_content
                    FROM chat_messages
                    WHERE thread_id = t.thread_id
                    AND message_role = 'user'
                    ORDER BY created_at ASC
                    LIMIT 1
                ) as first_user_message
            FROM chat_threads t
            LEFT JOIN LATERAL (
                SELECT message_content, created_at, message_role, agent_endpoint
                FROM chat_messages
                WHERE thread_id = t.thread_id
                ORDER BY created_at DESC
                LIMIT 1
            ) m ON true
            WHERE t.user_id = %s
            ORDER BY COALESCE(m.created_at, t.updated_at) DESC
        """
        return self.db.execute_query(query, (user_id,))

    def create_thread(self, user_id: str = "dev_user", metadata: Dict = None) -> str:
        """Create a new chat thread"""
        query = """
            INSERT INTO chat_threads (user_id, metadata)
            VALUES (%s, %s)
            RETURNING thread_id, created_at
        """
        result = self.db.execute_query_one(
            query,
            (user_id, Json(metadata or {}))
        )
        logger.info(f"Created thread {result['thread_id']} for user {user_id}")
        return str(result['thread_id'])

    def save_message(self,
                    thread_id: str,
                    user_id: str,
                    message_role: str,
                    message_content: str,
                    agent_endpoint: str = None,
                    metadata: Dict = None) -> str:
        """Save a chat message with Unicode normalization applied at write-time"""
        # Normalize Unicode at write-time to avoid repeated processing on reads
        normalized_content = normalize_unicode(message_content)

        query = """
            INSERT INTO chat_messages (thread_id, user_id, message_role, message_content, agent_endpoint, metadata)
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING message_id, created_at
        """
        result = self.db.execute_query_one(
            query,
            (thread_id, user_id, message_role, normalized_content, agent_endpoint, Json(metadata or {}))
        )
        logger.info(f"Saved message {result['message_id']} in thread {thread_id}")
        return str(result['message_id'])

    def update_feedback(self,
                       message_id: str,
                       thread_id: str,
                       user_id: str,
                       feedback_type: str) -> Dict:
        """Update or insert feedback for a message"""
        # Handle 'none' feedback type by deleting existing feedback
        if feedback_type == 'none':
            query = """
                DELETE FROM message_feedback
                WHERE message_id = %s AND thread_id = %s AND user_id = %s
                RETURNING feedback_id
            """
            result = self.db.execute_query_one(
                query,
                (message_id, thread_id, user_id)
            )
            return {"deleted": True, "feedback_id": str(result['feedback_id']) if result else None}

        # Upsert feedback
        query = """
            INSERT INTO message_feedback (message_id, thread_id, user_id, feedback_type)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (user_id, message_id, thread_id)
            DO UPDATE SET
                feedback_type = EXCLUDED.feedback_type,
                updated_at = CURRENT_TIMESTAMP
            RETURNING feedback_id, feedback_type, created_at, updated_at
        """
        result = self.db.execute_query_one(
            query,
            (message_id, thread_id, user_id, feedback_type)
        )
        logger.info(f"Updated feedback for message {message_id}: {feedback_type}")
        return {
            "feedback_id": str(result['feedback_id']),
            "feedback_type": result['feedback_type'],
            "created_at": result['created_at'].isoformat(),
            "updated_at": result['updated_at'].isoformat()
        }

    def get_thread_messages(
        self,
        thread_id: str,
        limit: int = None,
        offset: int = 0
    ) -> List[Dict]:
        """
        Get messages in a thread with optional pagination.

        Args:
            thread_id: The thread UUID
            limit: Maximum number of messages to return (None = all messages, backward compatible)
            offset: Number of messages to skip (default 0)

        Returns:
            List of message dictionaries ordered by created_at ASC
        """
        query = """
            SELECT
                m.message_id,
                m.user_id,
                m.message_role,
                m.message_content,
                m.agent_endpoint,
                m.created_at,
                m.metadata,
                f.feedback_type
            FROM chat_messages m
            LEFT JOIN message_feedback f ON m.message_id = f.message_id
            WHERE m.thread_id = %s
            ORDER BY m.created_at ASC
        """

        # Add pagination if limit is specified
        if limit is not None:
            query += f" LIMIT {int(limit)} OFFSET {int(offset)}"

        results = self.db.execute_query(query, (thread_id,))
        return [{
            "message_id": str(r['message_id']),
            "user_id": r['user_id'],
            "message_role": r['message_role'],  # Changed from "role" to match Flutter code
            # Note: Unicode normalization now happens at write-time in save_message()
            # This normalize_unicode call handles legacy messages that weren't normalized
            "message_content": normalize_unicode(r['message_content']),
            "agent_endpoint": r['agent_endpoint'],
            "created_at": r['created_at'].isoformat(),
            "metadata": r['metadata'],
            "feedback": r['feedback_type']
        } for r in results]

    def get_feedback_stats(self, thread_id: str = None) -> List[Dict]:
        """Get feedback statistics"""
        if thread_id:
            query = """
                SELECT * FROM message_feedback_stats
                WHERE thread_id = %s
            """
            params = (thread_id,)
        else:
            query = "SELECT * FROM message_feedback_stats"
            params = None

        results = self.db.execute_query(query, params)
        return [{
            "message_id": str(r['message_id']),
            "thread_id": str(r['thread_id']),
            "message_role": r['message_role'],
            "like_count": r['like_count'],
            "dislike_count": r['dislike_count'],
            "total_feedback": r['total_feedback']
        } for r in results]


    def update_message_tts_cache(self, message_id: str, tts_cache: Optional[Dict]) -> bool:
        """Update message metadata with TTS cache info, or clear it if None"""
        if tts_cache is None:
            # Clear the tts_cache key from metadata
            query = """
                UPDATE chat_messages
                SET metadata = COALESCE(metadata, '{}'::jsonb) - 'tts_cache'
                WHERE message_id = %s
                RETURNING message_id
            """
            result = self.db.execute_query_one(query, (message_id,))
        else:
            # Set/update the tts_cache
            query = """
                UPDATE chat_messages
                SET metadata = COALESCE(metadata, '{}'::jsonb) || %s
                WHERE message_id = %s
                RETURNING message_id
            """
            result = self.db.execute_query_one(
                query,
                (Json({"tts_cache": tts_cache}), message_id)
            )
        return result is not None

    def get_message_tts_cache(self, message_id: str, user_id: str) -> Optional[Dict]:
        """Get TTS cache info for a message, verifying user ownership"""
        query = """
            SELECT metadata->'tts_cache' as tts_cache
            FROM chat_messages
            WHERE message_id = %s AND user_id = %s
        """
        result = self.db.execute_query_one(query, (message_id, user_id))
        return result['tts_cache'] if result and result.get('tts_cache') else None

    def initialize_schema(self):
        """Initialize database schema"""
        schema_path = os.path.join(os.path.dirname(__file__), 'schema.sql')
        if os.path.exists(schema_path):
            with open(schema_path, 'r') as f:
                schema = f.read()

            conn = None
            try:
                conn = self.db.get_connection()
                with conn.cursor() as cursor:
                    cursor.execute(schema)
                    conn.commit()
                logger.info("Database schema initialized successfully")
            except Exception as e:
                if conn:
                    conn.rollback()
                # Only log as debug for expected errors like existing objects
                if "already exists" in str(e):
                    logger.debug(f"Schema objects already exist: {e}")
                else:
                    logger.error(f"Schema initialization failed: {e}")
                    raise
            finally:
                if conn:
                    self.db.put_connection(conn)

# Global database instances
db_manager = None
chat_db = None

def initialize_database():
    """Initialize database connections"""
    global db_manager, chat_db
    db_manager = DatabaseManager()
    chat_db = ChatDatabase(db_manager)
    # Initialize schema on first run
    try:
        chat_db.initialize_schema()
    except Exception as e:
        logger.warning(f"Schema initialization skipped or failed: {e}")
    return chat_db