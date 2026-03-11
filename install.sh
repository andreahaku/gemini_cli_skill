#!/bin/bash
set -e
echo "Installing Gemini MCP Server dependencies..."
npm install
echo "Building project..."
npm run build
echo "Installation complete!"
