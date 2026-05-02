#!/bin/bash

source "$(dirname "$0")/../config.sh"

echo "=========================================="
echo " LESSON 9: Vulnerable Dependencies - Fix Verification"
echo "=========================================="

WORK_DIR="/tmp/dvsa_dep_verify"
mkdir -p "$WORK_DIR"

echo ""
echo "[TEST 1] Downloading patched Lambda to verify dependency removal..."

DOWNLOAD_URL=$(aws lambda get-function \
  --function-name "DVSA-ORDER-MANAGER" \
  --region "$AWS_REGION" \
  --query 'Code.Location' \
  --output text 2>/dev/null)

curl -s "$DOWNLOAD_URL" -o "$WORK_DIR/lambda.zip" 2>/dev/null
mkdir -p "$WORK_DIR/extracted"
unzip -q "$WORK_DIR/lambda.zip" -d "$WORK_DIR/extracted" 2>/dev/null

if [ -d "$WORK_DIR/extracted/node_modules/node-serialize" ]; then
    echo "   ❌ node-serialize still present in node_modules — fix not applied."
else
    echo "   ✅ node-serialize is no longer in node_modules."
fi

if [ -f "$WORK_DIR/extracted/package.json" ]; then
    HAS_DEP=$(python3 -c "
import json
with open('$WORK_DIR/extracted/package.json') as f:
    pkg = json.load(f)
print('yes' if 'node-serialize' in pkg.get('dependencies', {}) else 'no')
" 2>/dev/null)
    if [ "$HAS_DEP" = "no" ]; then
        echo "   ✅ node-serialize removed from package.json dependencies."
    else
        echo "   ❌ node-serialize still listed in package.json."
    fi
fi

echo ""
echo "[TEST 2] Checking order-manager.js for unserialize calls..."
MANAGER="$WORK_DIR/extracted/order-manager.js"
if [ -f "$MANAGER" ]; then
    UNSAFE=$(grep -n "unserialize\|node-serialize" "$MANAGER" 2>/dev/null | grep -v "^.*REMOVED\|^.*PATCHED\|^.*//")
    if [ -z "$UNSAFE" ]; then
        echo "   ✅ No active unserialize calls found in order-manager.js."
    else
        echo "   ❌ unserialize still active:"
        echo "$UNSAFE" | sed 's/^/   /'
    fi
fi

echo ""
echo "[TEST 3] Running npm audit on patched Lambda..."
cd "$WORK_DIR/extracted"
if command -v npm &>/dev/null; then
    AUDIT_OUT=$(npm audit --audit-level=high 2>/dev/null)
    HIGH_COUNT=$(echo "$AUDIT_OUT" | grep -i "high\|critical" | grep -c "vulnerabilit" || echo "0")
    echo "   npm audit results:"
    echo "$AUDIT_OUT" | tail -8 | sed 's/^/   /'
    if [ "$HIGH_COUNT" = "0" ]; then
        echo "   ✅ No high/critical vulnerabilities found."
    else
        echo "   ⚠️  $HIGH_COUNT high/critical vulnerabilities remain."
    fi
fi
cd - > /dev/null

echo ""
echo "[TEST 4] Sending original RCE payload (should be rejected)..."
RESPONSE=$(curl -s -X POST "${API_URL}/order" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "_$$ND_FUNC$$_function(){ var fs = require(\"fs\"); fs.writeFileSync(\"/tmp/still_vuln.txt\", \"still vulnerable\"); console.error(\"STILL VULNERABLE\"); }()",
    "cart-id": ""
  }')
echo "   API response: $RESPONSE"

echo ""
echo "   Check CloudWatch /aws/lambda/DVSA-ORDER-MANAGER for recent logs."
echo "   If 'STILL VULNERABLE' does NOT appear → ✅ Fix is effective."
echo "   If it DOES appear → ❌ Lambda was not redeployed correctly."

LOG_GROUP="/aws/lambda/DVSA-ORDER-MANAGER"
LATEST_STREAM=$(aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --order-by LastEventTime --descending --max-items 1 \
  --query 'logStreams[0].logStreamName' --output text \
  --region "$AWS_REGION" 2>/dev/null)

if [ -n "$LATEST_STREAM" ] && [ "$LATEST_STREAM" != "None" ]; then
    RECENT_LOGS=$(aws logs get-log-events \
      --log-group-name "$LOG_GROUP" \
      --log-stream-name "$LATEST_STREAM" \
      --limit 15 --region "$AWS_REGION" \
      --query 'events[*].message' --output text 2>/dev/null)

    if echo "$RECENT_LOGS" | grep -qi "STILL VULNERABLE\|FILE READ"; then
        echo "   ❌ RCE evidence found in logs — fix not effective."
    else
        echo "   ✅ No RCE evidence in recent CloudWatch logs."
    fi
fi

rm -rf "$WORK_DIR"

echo ""
echo "=========================================="
echo " Lesson 9 fix verification complete."
echo "=========================================="
