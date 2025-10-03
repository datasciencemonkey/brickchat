# BrickChat - Deployment Summary

## ✅ GOOD NEWS: Full Stack Deployment is Possible!

After clarifying the Databricks Apps file size constraint, **you CAN deploy the complete Flutter + Backend app**.

## Size Constraint Clarification

**Databricks Apps Limit**: 10 MB **per file** (NOT total project size)

### Your Project File Sizes:
- ✅ Largest file: **6.7 MB** (canvaskit.wasm)
- ✅ All files: **< 10 MB each**
- ✅ Status: **PASSES all size checks!**

## Deployment Options

You now have **TWO deployment strategies**:

### Option 1: Full Stack Deployment (Recommended)
Deploy everything (Flutter frontend + FastAPI backend) to Databricks Apps in one unified app.

**Pros:**
- Single deployment
- Simpler architecture
- Single URL to manage
- No CORS configuration needed

**Use this script:**
```bash
./deploy.sh
```

**Files used:**
- `app.yaml` - App configuration
- `app.py` - FastAPI with static file serving
- `requirements.txt` - Python dependencies
- `routers/` - API routes
- `build/web/` - Flutter web app

**Result:**
- URL: `https://adb-984752964297111.11.azuredatabricks.net/apps/brickchat`
- Serves both frontend UI and API endpoints

---

### Option 2: Split Deployment (Backend Only)
Deploy only the backend to Databricks Apps, host frontend elsewhere.

**Pros:**
- Smaller Databricks deployment
- Frontend on CDN (faster loading)
- Independent scaling
- Can use free frontend hosting

**Cons:**
- Two deployments to manage
- CORS configuration required
- More complex setup

**Use this script:**
```bash
./deploy-backend.sh
```

**Files used:**
- `app.yaml` - App configuration
- `app_backend_only.py` - API-only FastAPI (no static files)
- `requirements.txt` - Python dependencies
- `routers/` - API routes

**Frontend hosting options:**
- GitHub Pages (free)
- Cloudflare Pages (free)
- Vercel (free)
- Netlify (free)

**See:** [DEPLOYMENT_BACKEND_ONLY.md](DEPLOYMENT_BACKEND_ONLY.md) for details

---

## Recommended Approach

### For Most Users: **Option 1 (Full Stack)**

Simplest deployment with everything in one place.

```bash
# One-command deployment
./deploy.sh
```

### When to use Option 2 (Split):
- You want CDN performance for frontend
- You plan to scale frontend/backend independently
- You want to use a specific frontend hosting service
- You need to update frontend frequently without backend redeploys

## Quick Start (Full Stack)

### Prerequisites (One-Time Setup)

```bash
# 1. Install Databricks CLI
pip install databricks-cli

# 2. Configure authentication
databricks configure --token
# Enter: https://adb-984752964297111.11.azuredatabricks.net
# Enter: Your personal access token

# 3. Create secrets
databricks secrets create-scope brickchat-secrets
databricks secrets put-secret brickchat-secrets databricks-token
databricks secrets put-secret brickchat-secrets deepgram-api-key
databricks secrets put-secret brickchat-secrets replicate-api-token
```

### Deploy

```bash
./deploy.sh
```

This will:
1. Build Flutter web app with WASM
2. Verify all files are under 10MB per-file limit ✅
3. Sync project to Databricks workspace
4. Deploy as `brickchat` app

### Access Your App

```
https://adb-984752964297111.11.azuredatabricks.net/apps/brickchat
```

## File Size Details

```
Backend files:
  app.yaml:         4 KB
  app.py:           4 KB
  requirements.txt: 4 KB
  routers/:         48 KB
  Total:            60 KB

Flutter build/web (largest files):
  canvaskit.wasm:   6.7 MB  ✅ (< 10 MB)
  chromium/*.wasm:  5.4 MB  ✅ (< 10 MB)
  skwasm_heavy:     4.7 MB  ✅ (< 10 MB)
  skwasm.wasm:      3.3 MB  ✅ (< 10 MB)
  main.dart.js:     2.8 MB  ✅ (< 10 MB)
  main.dart.wasm:   2.6 MB  ✅ (< 10 MB)

Total project:      ~31 MB (acceptable - limit is per-file)
Per-file check:     ALL PASS ✅
```

## Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Full stack deployment guide
- **[DEPLOYMENT_BACKEND_ONLY.md](DEPLOYMENT_BACKEND_ONLY.md)** - Split deployment guide
- **[QUICKSTART.md](QUICKSTART.md)** - Quick reference
- **[app.yaml](app.yaml)** - Databricks app configuration

## Scripts

- **[deploy.sh](deploy.sh)** - Full stack deployment (RECOMMENDED)
- **[deploy-backend.sh](deploy-backend.sh)** - Backend-only deployment

## Common Commands

```bash
# Deploy app
./deploy.sh

# Check app status
databricks apps get brickchat

# View logs
databricks apps logs brickchat

# View logs in real-time
databricks apps logs brickchat --follow

# List all apps
databricks apps list

# Stop app
databricks apps stop brickchat

# Start app
databricks apps start brickchat

# Delete app
databricks apps delete brickchat
```

## Features Verified

- ✅ Chat with Databricks AI endpoint
- ✅ Text-to-Speech (Deepgram & Replicate)
- ✅ Voice input (Speech-to-Text)
- ✅ Stream mode toggle
- ✅ Eager mode toggle (fixed state sync)
- ✅ Theme switching (light/dark)
- ✅ Settings persistence
- ✅ Real-time streaming responses
- ✅ WASM build optimized

## Support

For issues:
1. Check logs: `databricks apps logs brickchat --follow`
2. Verify secrets: `databricks secrets list-secrets brickchat-secrets`
3. Test health: `curl <app-url>/api/health`
4. Review documentation files above

---

**Ready to deploy?** Run `./deploy.sh` 🚀
