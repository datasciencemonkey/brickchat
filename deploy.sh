#!/bin/bash

# BrickChat - Databricks Apps Deployment Script
# This script automates the deployment process

set -e  # Exit on error

echo "========================================="
echo "BrickChat - Databricks Apps Deployment"
echo "========================================="
echo ""

# Configuration
APP_NAME="brickchat"
DATABRICKS_USERNAME=$(databricks current-user me 2>/dev/null | jq -r .userName || echo "datasciencemonkey@gmail.com")
WORKSPACE_PATH="/Workspace/Users/$DATABRICKS_USERNAME/$APP_NAME"

echo "Configuration:"
echo "  App Name: $APP_NAME"
echo "  Databricks User: $DATABRICKS_USERNAME"
echo "  Workspace Path: $WORKSPACE_PATH"
echo ""

# Step 1: Build Flutter Web App
echo "Step 1/4: Building Flutter web app..."
flutter build web --wasm
if [ $? -ne 0 ]; then
    echo "❌ Flutter build failed!"
    exit 1
fi
echo "✅ Flutter web build completed"
echo ""

# Step 2: Verify required files
echo "Step 2/4: Verifying required files..."
REQUIRED_FILES=("app.yaml" "app.py" "requirements.txt" "routers" "build/web")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -e "$file" ]; then
        echo "❌ Required file/directory missing: $file"
        exit 1
    fi
    echo "  ✓ Found: $file"
done
echo "✅ All required files present"
echo ""

# Step 2.5: Check for files over 10MB (per-file limit)
echo "Checking per-file size limit (10MB)..."
LARGE_FILES=$(find . -type f -size +10M 2>/dev/null | grep -v ".git" || true)
if [ ! -z "$LARGE_FILES" ]; then
    echo "❌ Files exceeding 10MB per-file limit:"
    echo "$LARGE_FILES"
    exit 1
fi
LARGEST=$(find build/web -type f -exec du -h {} \; 2>/dev/null | sort -rh | head -1 || echo "N/A")
echo "  Largest file: $LARGEST"
echo "✅ All files under 10MB limit"
echo ""

# Step 3: Sync to Databricks Workspace
echo "Step 3/4: Syncing project to Databricks workspace..."
echo "  Uploading to: $WORKSPACE_PATH"
databricks sync . "$WORKSPACE_PATH"
if [ $? -ne 0 ]; then
    echo "❌ Sync failed!"
    exit 1
fi
echo "✅ Project synced successfully"
echo ""

# Step 4: Deploy the app
echo "Step 4/4: Deploying app to Databricks Apps..."
databricks apps deploy "$APP_NAME" \
  --source-code-path "$WORKSPACE_PATH"
if [ $? -ne 0 ]; then
    echo "❌ Deployment failed!"
    exit 1
fi
echo "✅ App deployed successfully"
echo ""

# Get app details
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "App Status:"
databricks apps get "$APP_NAME" 2>/dev/null || echo "  (Run 'databricks apps get $APP_NAME' to check status)"
echo ""
echo "Next Steps:"
echo "  1. Check logs: databricks apps logs $APP_NAME"
echo "  2. View app status: databricks apps get $APP_NAME"
echo "  3. Access your app at: https://adb-984752964297111.11.azuredatabricks.net/apps/$APP_NAME"
echo ""
echo "To view logs in real-time:"
echo "  databricks apps logs $APP_NAME --follow"
echo ""
