# PostgreSQL Setup for BrickChat

##### Pre-req:
 - Ensure lakebase database is set up
 - Enable native role login

## Create User and Database

```sql
-- Create the service user
CREATE USER service_brickchat WITH PASSWORD 'brickchatUI123!';

-- Create the database
CREATE DATABASE brickchat;

-- Grant database connection privileges
GRANT CONNECT ON DATABASE brickchat TO service_brickchat;

-- Grant all privileges on the database
GRANT ALL PRIVILEGES ON DATABASE brickchat TO service_brickchat;
```

## Grant Schema and Table Privileges

**IMPORTANT:** Connect to the `brickchat` database first, then run the GRANT commands:

```sql
-- Connect to brickchat database
\c brickchat

-- Grant CREATE privilege on public schema (required for table creation)
GRANT CREATE ON SCHEMA public TO service_brickchat;

-- Grant schema privileges
GRANT ALL PRIVILEGES ON SCHEMA public TO service_brickchat;

-- Grant privileges on all existing tables
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_brickchat;

-- Grant privileges on all existing sequences
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_brickchat;

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_brickchat;

-- Set default privileges for future sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO service_brickchat;
```

## Update Environment Variables

Add the following to your `backend/.env` file:

```bash
PGHOST=your-instance-name
PGDATABASE=brickchat
PGUSER=service_brickchat
PG_PASS=some-password
```

## Create Database Schema

After setting up the user, privileges, and environment variables, initialize the schema by running the initialization script from the backend directory:

```bash
cd backend
uv run python -c "from dotenv import load_dotenv; load_dotenv(); from database import ChatDatabase, DatabaseManager; chat_db = ChatDatabase(DatabaseManager()); chat_db.initialize_schema()"
```

This will create all necessary tables (chat_threads, chat_messages, message_feedback) from `backend/schema.sql`.

**Note:** The `run_migration.py` script is only needed for existing databases to add the `agent_endpoint` column. For new setups, the column is already included in `schema.sql`.

## Change User Password (if needed)

```sql
ALTER USER service_brickchat WITH PASSWORD 'new_password';
```
