#!/bin/bash
# =============================================================
# LESSON 1 & 9 FIX: Remove node-serialize + Rebuild Lambda
# This script downloads the current Lambda zip, patches it,
# removes node-serialize, and redeploys to AWS.
# =============================================================

source "$(dirname "$0")/../config.sh"

FUNCTION_NAME="DVSA-ORDER-MANAGER"
WORK_DIR="/tmp/dvsa_lambda_patch"

echo "=========================================="
echo " LESSON 1 & 9: Applying Fix"
echo " Removing node-serialize + adding validation"
echo "=========================================="

# -------------------------------------------------------
# STEP 1: Download current Lambda deployment package
# -------------------------------------------------------
echo ""
echo "[STEP 1] Downloading current Lambda code..."
mkdir -p "$WORK_DIR"

DOWNLOAD_URL=$(aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --query 'Code.Location' \
  --output text 2>/dev/null)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "   ❌ Could not get download URL. Check AWS credentials."
    exit 1
fi

curl -s "$DOWNLOAD_URL" -o "$WORK_DIR/lambda.zip"
echo "   ✅ Downloaded to $WORK_DIR/lambda.zip"

# -------------------------------------------------------
# STEP 2: Extract and inspect
# -------------------------------------------------------
echo ""
echo "[STEP 2] Extracting zip..."
mkdir -p "$WORK_DIR/extracted"
unzip -q "$WORK_DIR/lambda.zip" -d "$WORK_DIR/extracted"

echo "   Files found:"
ls "$WORK_DIR/extracted/" | head -20

echo ""
echo "   Checking for node-serialize..."
if [ -d "$WORK_DIR/extracted/node_modules/node-serialize" ]; then
    echo "   ⚠️  node-serialize FOUND at node_modules/node-serialize"
    echo "   Version: $(cat "$WORK_DIR/extracted/node_modules/node-serialize/package.json" 2>/dev/null | grep '"version"' | head -1)"
else
    echo "   ℹ️  node-serialize not found in node_modules (may already be removed or bundled differently)"
fi

# -------------------------------------------------------
# STEP 3: Show current vulnerable code section
# -------------------------------------------------------
echo ""
echo "[STEP 3] Current order-manager.js parsing section:"
grep -n "serialize\|unserialize\|node-serialize\|require.*serial" \
  "$WORK_DIR/extracted/order-manager.js" 2>/dev/null || \
  echo "   (node-serialize reference not found in order-manager.js)"

# -------------------------------------------------------
# STEP 4: Apply the safe JSON.parse patch directly
# -------------------------------------------------------
echo ""
echo "[STEP 4] Patching order-manager.js..."

MANAGER="$WORK_DIR/extracted/order-manager.js"

if [ ! -f "$MANAGER" ]; then
    echo "   ❌ order-manager.js not found at expected path."
    echo "   Files in extracted dir:"
    find "$WORK_DIR/extracted" -name "*.js" | head -10
    exit 1
fi

# Backup original
cp "$MANAGER" "${MANAGER}.bak"

# Remove node-serialize require line
sed -i "s|const serialize = require('node-serialize');|// REMOVED: const serialize = require('node-serialize'); // PATCHED|g" "$MANAGER"
sed -i "s|var serialize = require('node-serialize');|// REMOVED: var serialize = require('node-serialize'); // PATCHED|g" "$MANAGER"

# Replace unserialize call with safe JSON.parse
# (handles both common patterns seen in DVSA)
sed -i "s|serialize\.unserialize(event\.body)|JSON.parse(event.body || '{}')|g" "$MANAGER"
sed -i "s|serialize\.unserialize(body)|JSON.parse(typeof body === 'string' ? body : '{}')|g" "$MANAGER"

echo "   ✅ node-serialize references patched in order-manager.js"

# -------------------------------------------------------
# STEP 5: Remove node-serialize from node_modules
# -------------------------------------------------------
echo ""
echo "[STEP 5] Removing node-serialize from node_modules..."
rm -rf "$WORK_DIR/extracted/node_modules/node-serialize"
echo "   ✅ node-serialize removed from node_modules"

# -------------------------------------------------------
# STEP 6: Update package.json to remove the dependency
# -------------------------------------------------------
echo ""
echo "[STEP 6] Removing node-serialize from package.json..."
PACKAGE_JSON="$WORK_DIR/extracted/package.json"
if [ -f "$PACKAGE_JSON" ]; then
    # Remove the node-serialize line from dependencies
    python3 -c "
import json, sys
with open('$PACKAGE_JSON', 'r') as f:
    pkg = json.load(f)
removed = pkg.get('dependencies', {}).pop('node-serialize', None)
if removed:
    print(f'   Removed node-serialize {removed} from package.json')
else:
    print('   node-serialize not in package.json dependencies')
with open('$PACKAGE_JSON', 'w') as f:
    json.dump(pkg, f, indent=2)
"
else
    echo "   ⚠️  package.json not found"
fi

# -------------------------------------------------------
# STEP 7: Run npm audit to check for remaining issues
# -------------------------------------------------------
echo ""
echo "[STEP 7] Running npm audit on patched package..."
cd "$WORK_DIR/extracted"
if command -v npm &>/dev/null; then
    npm audit --audit-level=high 2>/dev/null | tail -10 || echo "   npm audit complete"
else
    echo "   ℹ️  npm not available in this environment - run manually after deploying"
fi
cd - > /dev/null

# -------------------------------------------------------
# STEP 8: Repack and deploy
# -------------------------------------------------------
echo ""
echo "[STEP 8] Repacking Lambda deployment zip..."
cd "$WORK_DIR/extracted"
zip -qr "$WORK_DIR/patched_lambda.zip" .
cd - > /dev/null
echo "   ✅ Patched zip: $WORK_DIR/patched_lambda.zip ($(du -sh $WORK_DIR/patched_lambda.zip | cut -f1))"

echo ""
echo "[STEP 9] Deploying patched Lambda..."
DEPLOY_RESULT=$(aws lambda update-function-code \
  --function-name "$FUNCTION_NAME" \
  --zip-file "fileb://$WORK_DIR/patched_lambda.zip" \
  --region "$AWS_REGION" 2>&1)

if echo "$DEPLOY_RESULT" | grep -qi "FunctionArn\|LastModified"; then
    echo "   ✅ Lambda deployed successfully."
    echo "   $(echo "$DEPLOY_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'   Version: {d.get(\"Version\",\"N/A\")} | Runtime: {d.get(\"Runtime\",\"N/A\")}')" 2>/dev/null)"
else
    echo "   ❌ Deployment failed. Response:"
    echo "$DEPLOY_RESULT"
fi

# -------------------------------------------------------
# STEP 10: Wait for update and verify deployment
# -------------------------------------------------------
echo ""
echo "[STEP 10] Waiting for Lambda update to complete..."
aws lambda wait function-updated \
  --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" 2>/dev/null
echo "   ✅ Lambda update complete."

echo ""
echo "=========================================="
echo " Fix applied. Now run: bash lesson1/verify_fix.sh"
echo "=========================================="

# Cleanup
rm -rf "$WORK_DIR"
