#!/bin/bash

# Build Flutter web app
echo "Building Flutter web app..."
flutter build web

# Create static directory if it doesn't exist
mkdir -p static

# Copy Flutter web build files to static directory
echo "Copying Flutter web build files..."
cp -r build/web/* static/

# Get Databricks username
DATABRICKS_USERNAME=$(databricks current-user me | jq -r .userName)
echo "Databricks username: $DATABRICKS_USERNAME"

# Sync files to Databricks workspace
echo "Syncing files to Databricks workspace..."
databricks sync . "/Users/$DATABRICKS_USERNAME/brickchat-web"

# Deploy the app
echo "Deploying app to Databricks Apps..."
databricks apps deploy brickchat-web --source-code-path "/Workspace/Users/$DATABRICKS_USERNAME/brickchat-web"

echo "Deployment complete!"


