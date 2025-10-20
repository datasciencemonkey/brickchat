# BrickChat Databricks Apps Troubleshooting

## Common Issues and Solutions

### Issue 1: "Error: Error:" message in chat

**Symptoms:**
- App loads but shows "Error: Error:" when trying to send a message
- Backend is running (`/health` endpoint works)

**Cause:** API connection issues

**Solutions:**

1. **Check API URL configuration:**
   - Verify `fastapi_service.dart` uses relative URLs (empty `baseUrl` for web)
   - Rebuild Flutter: `flutter build web --wasm`
   - Update deployment: `./update_deployment.sh`

2. **Check diagnostic endpoint:**
   ```bash
   curl https://your-databricks-app.com/debug/info
   ```
   This shows:
   - Current working directory
   - Whether build files exist
   - File listing

3. **Check logs in Databricks Apps:**
   ```bash
   databricks apps logs brickchat
   ```
   Look for:
   - "✓ Found build at: build/web" (good)
   - "✗ Flutter build not found!" (bad - redeploy)

### Issue 2: Backend runs but no frontend

**Symptoms:**
- `/health` returns success
- Root `/` shows JSON instead of Flutter app

**Cause:** Flutter build files not in deployment

**Solution:**
```bash
# Rebuild and update deployment
cd /path/to/brickchat
flutter build web --wasm
rm -rf deployment/build/web
cp -r build/web deployment/build/web/

# Redeploy
databricks apps deploy brickchat --source-code-path ./deployment
```

### Issue 3: CORS or security errors

**Symptoms:**
- Browser console shows CORS errors
- "Cross-Origin" policy violations

**Cause:** WASM headers interfering with API calls

**Solution:**
The app.py now only applies WASM headers to HTML pages, not API routes:
```python
if request.url.path == "/" or request.url.path.endswith(".html"):
    response.headers["Cross-Origin-Embedder-Policy"] = "credentialless"
    response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
```

If still having issues, check browser DevTools → Network tab for specific errors.

### Issue 4: Database connection errors

**Symptoms:**
- Chat sends but no response
- Logs show database errors

**Solution:**
1. **Check DATABASE_URL secret:**
   ```bash
   databricks secrets list --scope brickchat
   ```

2. **Verify database accessibility:**
   - Ensure PostgreSQL is accessible from Databricks
   - Check connection string format
   - Test with: `curl https://your-app.com/health`

3. **Update app.yaml:**
   ```yaml
   env:
     - name: DATABASE_URL
       valueFrom: "secret://brickchat/database-url"
   ```

### Issue 5: Environment variables not loading

**Symptoms:**
- "DATABRICKS_TOKEN not found" errors
- API calls to Databricks fail

**Solution:**
1. **Set secrets in Databricks:**
   ```bash
   databricks secrets create-scope --scope brickchat
   databricks secrets put --scope brickchat --key databricks-token
   databricks secrets put --scope brickchat --key database-url
   ```

2. **Update app.yaml to reference secrets:**
   ```yaml
   env:
     - name: DATABRICKS_TOKEN
       valueFrom: "secret://brickchat/databricks-token"
   ```

3. **Redeploy:**
   ```bash
   databricks apps deploy brickchat --source-code-path ./deployment
   ```

## Diagnostic Checklist

Run these checks in order:

### 1. Backend Health
```bash
curl https://your-app.com/health
# Expected: {"status": "healthy"}
```

### 2. Diagnostic Info
```bash
curl https://your-app.com/debug/info
# Check: build_exists should be true
```

### 3. Frontend Loads
```
Visit: https://your-app.com/
# Should show Flutter app, not JSON
```

### 4. API Connectivity
Open browser DevTools → Network tab, send a message, check:
- Request URL should be relative: `/api/chat/send`
- Not absolute: `http://localhost:8000/api/chat/send`

### 5. Logs
```bash
databricks apps logs brickchat --follow
# Look for errors, warnings
```

## Quick Fixes

### Redeploy Everything
```bash
cd /path/to/brickchat
./deployment/update_deployment.sh
databricks apps deploy brickchat --source-code-path ./deployment
```

### Reset Deployment
```bash
# Delete app
databricks apps delete brickchat

# Redeploy fresh
databricks apps deploy brickchat --source-code-path ./deployment
```

### Local Testing
Test deployment package locally before deploying:
```bash
cd deployment
uv run uvicorn app:app --host 0.0.0.0 --port 8000

# Visit: http://localhost:8000
# Should show Flutter app and work correctly
```

## Getting Help

If issues persist:

1. **Collect information:**
   - App logs: `databricks apps logs brickchat > logs.txt`
   - Diagnostic info: `curl https://your-app.com/debug/info > debug.json`
   - Browser console errors (screenshot)

2. **Check common causes:**
   - Build files not copied to deployment/
   - Secrets not configured correctly
   - Database connection issues
   - API URL hardcoded to localhost

3. **Contact support** with logs and diagnostics

## Production Checklist

Before deploying to production:

- [ ] Test locally: `cd deployment && uv run uvicorn app:app`
- [ ] Verify build exists: `ls deployment/build/web/index.html`
- [ ] Secrets configured in Databricks
- [ ] Database accessible from Databricks
- [ ] CORS configured correctly (if using custom domain)
- [ ] Logs reviewed for errors
- [ ] `/health` endpoint returns success
- [ ] `/debug/info` shows correct paths
