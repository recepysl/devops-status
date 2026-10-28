#!/usr/bin/env bash
set -euo pipefail

APP="/Applications/DevOpsStatus.app"
BUNDLE_ID="io.github.recepysl.devops-status"

pkill -f "DevOpsStatus.app/Contents/MacOS/DevOpsStatus" 2>/dev/null || true
rm -rf "$APP"
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "✓ Removed DevOps Status and its preferences."
echo "  If it still appears under System Settings → General → Login Items, remove it there."
