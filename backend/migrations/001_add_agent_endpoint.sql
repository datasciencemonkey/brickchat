-- Migration: Add agent_endpoint column to chat_messages table
-- This tracks which agent/model endpoint was used for each message

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS agent_endpoint VARCHAR(255);

-- Add index for querying by agent endpoint
CREATE INDEX IF NOT EXISTS idx_chat_messages_agent_endpoint ON chat_messages(agent_endpoint);
