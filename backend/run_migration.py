"""Run database migrations"""
import os
from dotenv import load_dotenv
from database import DatabaseManager
import logging

# Load environment variables
load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def run_migration():
    """Apply the agent_endpoint migration"""
    db_manager = DatabaseManager()

    migration_sql = """
    -- Migration: Add agent_endpoint column to chat_messages table
    ALTER TABLE chat_messages
    ADD COLUMN IF NOT EXISTS agent_endpoint VARCHAR(255);

    -- Add index for querying by agent endpoint
    CREATE INDEX IF NOT EXISTS idx_chat_messages_agent_endpoint ON chat_messages(agent_endpoint);
    """

    conn = None
    try:
        conn = db_manager.get_connection()
        with conn.cursor() as cursor:
            cursor.execute(migration_sql)
            conn.commit()
        logger.info("✅ Migration completed successfully - agent_endpoint column added")
    except Exception as e:
        if conn:
            conn.rollback()
        logger.error(f"❌ Migration failed: {e}")
        raise
    finally:
        if conn:
            db_manager.put_connection(conn)

if __name__ == "__main__":
    run_migration()
