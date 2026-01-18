#!/bin/bash

# BrickChat - Update Deployment Script
# This script rebuilds the Flutter app and updates the deployment directory

set -e  # Exit on error

echo "🚀 BrickChat Deployment Updater"
echo "================================"
echo ""

# Step 1: Build Flutter WASM
echo "📦 Building Flutter WASM..."
cd ..
flutter build web --wasm

# Step 2: Update deployment directory
# Note: deployment/app.py expects build/ (not build/web/)
echo "📁 Updating deployment directory..."
rm -rf deployment/build
mkdir -p deployment/build
cp -r build/web/* deployment/build/

# Step 3: Copy backend files (in case they changed)
# WARNING: backend/app.py uses build/web/ paths, deployment/app.py uses build/ paths
# Only copy app.py if you've updated the paths, otherwise skip it
echo "🔧 Updating backend files..."
echo "⚠️  Skipping app.py (different build paths - edit manually if needed)"
# cp backend/app.py deployment/  # Uncomment only if paths are aligned
cp backend/database.py deployment/
cp backend/document_service.py deployment/
cp backend/auth.py deployment/
cp backend/schema.sql deployment/
cp backend/run_migration.py deployment/ 2>/dev/null || true
cp backend/routers/__init__.py deployment/routers/ 2>/dev/null || true
cp backend/routers/*.py deployment/routers/ 2>/dev/null || true
cp -r backend/migrations/* deployment/migrations/ 2>/dev/null || true

# Step 4: Update requirements.txt
echo "📋 Updating requirements.txt..."
cd backend
uv pip freeze > ../deployment/requirements.txt
cd ..

# Step 5: Show deployment size
echo ""
echo "✅ Deployment updated successfully!"
echo ""
echo "📊 Deployment size:"
du -sh deployment/

echo ""
echo "🎯 Next steps:"
echo "   1. Test locally: cd deployment && uv run uvicorn app:app --host 0.0.0.0 --port 8000"
echo "   2. Deploy to Databricks: databricks apps deploy brickchat --source-code-path ./deployment"
echo ""
