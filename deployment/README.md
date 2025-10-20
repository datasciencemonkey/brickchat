# BrickChat - Databricks Apps Deployment

This directory contains all files needed to deploy BrickChat to Databricks Apps.

## Directory Structure

```
deployment/
├── app.yaml              # Databricks Apps configuration
├── app.py                # FastAPI application entry point
├── database.py           # Database configuration
├── schema.sql            # Database schema
├── requirements.txt      # Python dependencies
├── routers/              # API endpoints
├── migrations/           # Database migrations
├── build/web/            # Flutter WASM build (frontend)
└── .env.example          # Environment variables template
```

## Deployment Steps

### 1. Prerequisites

- Databricks workspace with Apps enabled
- Databricks CLI installed and configured
- PostgreSQL database (or Databricks SQL)
- Databricks secrets configured

### 2. Configure Secrets

Create Databricks secrets for sensitive values:

```bash
# Create secret scope (if not exists)
databricks secrets create-scope --scope brickchat

# Add secrets
databricks secrets put --scope brickchat --key databricks-token
databricks secrets put --scope brickchat --key database-url
```

### 3. Update app.yaml

Edit `app.yaml` and update the secret references:

```yaml
env:
  - name: DATABRICKS_TOKEN
    valueFrom: "secret://brickchat/databricks-token"
  - name: DATABASE_URL
    valueFrom: "secret://brickchat/database-url"
```

### 4. Deploy

```bash
# From the deployment directory
databricks apps deploy brickchat \
  --source-code-path . \
  --config app.yaml
```

### 5. Verify Deployment

```bash
# Check app status
databricks apps get brickchat

# View logs
databricks apps logs brickchat
```

## Architecture

- **Frontend**: Flutter WASM application served as static files
- **Backend**: FastAPI serving both API endpoints and frontend
- **Database**: PostgreSQL for chat history and user data
- **Port**: 8000 (configurable in app.yaml)

## API Endpoints

- `GET /` - Flutter web application
- `GET /health` - Health check endpoint
- `POST /api/chat/send` - Send chat message (streaming)
- `GET /api/chat/history` - Get chat history
- `POST /api/chat/feedback` - Submit message feedback

## Environment Variables

See `.env.example` for required environment variables.

## Troubleshooting

### App won't start
- Check logs: `databricks apps logs brickchat`
- Verify secrets are configured correctly
- Ensure database is accessible

### Frontend not loading
- Verify `build/web/` directory contains Flutter WASM files
- Check FastAPI is serving static files from correct path

### Database connection issues
- Verify DATABASE_URL format
- Check network connectivity from Databricks Apps
- Ensure database accepts connections from Databricks

## Local Testing

To test locally before deployment:

```bash
# Set environment variables
cp .env.example .env
# Edit .env with your values

# Install dependencies
uv pip install -r requirements.txt

# Run application
uv run uvicorn app:app --host 0.0.0.0 --port 8000
```

Access at: http://localhost:8000

## Support

For issues or questions, contact your Databricks administrator.
