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
echo "📁 Updating deployment directory..."
rm -rf deployment/build/web
mkdir -p deployment/build/web
cp -r build/web/* deployment/build/web/

# Step 3: Copy backend files (in case they changed)
echo "🔧 Updating backend files..."
cp backend/app.py deployment/
cp backend/database.py deployment/
cp backend/schema.sql deployment/
cp backend/routers/* deployment/routers/ 2>/dev/null || true
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
