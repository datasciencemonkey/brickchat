-- Create schema for BrickChat feedback system
-- This schema captures user feedback (likes/dislikes) for chat messages

-- Create threads table to track conversations
CREATE TABLE IF NOT EXISTS chat_threads (
    thread_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Create messages table to store all messages in threads
CREATE TABLE IF NOT EXISTS chat_messages (
    message_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID NOT NULL REFERENCES chat_threads(thread_id) ON DELETE CASCADE,
    user_id VARCHAR(255) NOT NULL,
    message_role VARCHAR(20) NOT NULL CHECK (message_role IN ('user', 'assistant', 'system')),
    message_content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Create feedback table for likes/dislikes
CREATE TABLE IF NOT EXISTS message_feedback (
    feedback_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES chat_messages(message_id) ON DELETE CASCADE,
    thread_id UUID NOT NULL REFERENCES chat_threads(thread_id) ON DELETE CASCADE,
    user_id VARCHAR(255) NOT NULL,
    feedback_type VARCHAR(20) CHECK (feedback_type IN ('like', 'dislike', 'none')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    -- Ensure unique feedback per user, message, thread combination
    CONSTRAINT unique_user_message_feedback UNIQUE (user_id, message_id, thread_id)
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_chat_threads_user_id ON chat_threads(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_thread_id ON chat_messages(thread_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_created_at ON chat_messages(created_at);
CREATE INDEX IF NOT EXISTS idx_message_feedback_message_id ON message_feedback(message_id);
CREATE INDEX IF NOT EXISTS idx_message_feedback_user_thread ON message_feedback(user_id, thread_id);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers to auto-update updated_at
CREATE TRIGGER update_chat_threads_updated_at BEFORE UPDATE ON chat_threads
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_message_feedback_updated_at BEFORE UPDATE ON message_feedback
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create view for feedback statistics
CREATE OR REPLACE VIEW message_feedback_stats AS
SELECT
    m.message_id,
    m.thread_id,
    m.message_role,
    COUNT(CASE WHEN f.feedback_type = 'like' THEN 1 END) as like_count,
    COUNT(CASE WHEN f.feedback_type = 'dislike' THEN 1 END) as dislike_count,
    COUNT(f.feedback_id) as total_feedback
FROM chat_messages m
LEFT JOIN message_feedback f ON m.message_id = f.message_id
GROUP BY m.message_id, m.thread_id, m.message_role;