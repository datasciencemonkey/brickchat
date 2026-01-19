-- Autonomous Agents Registry Table
-- Stores curated Agent Bricks for L3 autonomous mode

CREATE TABLE IF NOT EXISTS autonomous_agents (
    agent_id VARCHAR(12) PRIMARY KEY,
    endpoint_url TEXT NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    databricks_metadata JSONB DEFAULT '{}',
    admin_metadata JSONB DEFAULT '{}',
    status VARCHAR(20) NOT NULL DEFAULT 'new' CHECK (status IN ('enabled', 'disabled', 'new')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index for fast status queries
CREATE INDEX IF NOT EXISTS idx_autonomous_agents_status ON autonomous_agents(status);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_autonomous_agents_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_autonomous_agents_updated ON autonomous_agents;
CREATE TRIGGER trigger_autonomous_agents_updated
    BEFORE UPDATE ON autonomous_agents
    FOR EACH ROW
    EXECUTE FUNCTION update_autonomous_agents_timestamp();
