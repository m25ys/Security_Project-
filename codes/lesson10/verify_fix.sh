#!/bin/bash

source "$(dirname "$0")/../config.sh"

echo "=========================================="
echo " LESSON 10: Unhandled Exceptions - Fix Verification"
echo "=========================================="

LEAKED=0
BLOCKED=0

run_test() {
    local DESC="$1"
    local PAYLOAD="$2"
    local AUTH="$3"

    RESP=$(curl -s -X POST "$API" \
      -H "content-type: application/json" \
      ${AUTH:+-H "authorization: $AUTH"} \
      --data-raw "$PAYLOAD")

    if echo "$RESP" | grep -qiE "stack|at Object\.|/var/task|TypeError|ReferenceError|SyntaxError|Cannot read prop|undefined is not|\.js:[0-9]"; then
        echo "   ❌ [$DESC] LEAKS internal details:"
        echo "$RESP" | head -3 | sed 's/^/      /'
        LEAKED=$((LEAKED+1))
    else
        echo "   ✅ [$DESC] Returns safe generic error: $(echo "$RESP" | jq -r '.msg // .message // "ok"' 2>/dev/null)"
        BLOCKED=$((BLOCKED+1))
    fi
}

echo ""
echo "[TEST GROUP 1] Malformed inputs — no stack traces allowed..."

run_test "empty body"           '{}'                                     ""
run_test "null action"          '{"action":null}'                        ""
run_test "numeric action"       '{"action":12345}'                       ""
run_test "wrong types"          '{"action":true,"order-id":[]}'          ""
run_test "path traversal"       '{"action":"get","order-id":"../../../../etc/passwd"}' "$TOKEN_B"
run_test "missing order-id"     '{"action":"billing"}'                   "$TOKEN_B"
run_test "deeply nested"        '{"action":{"nested":{"key":"val"}}}'    ""
run_test "unicode injection"    '{"action":"get","order-id":"\u0000\u001f"}' "$TOKEN_B"

echo ""
echo "[TEST GROUP 2] Valid request — must still succeed..."

if [ -n "$TOKEN_B" ] && [[ "$TOKEN_B" != PASTE* ]]; then
    VALID_RESP=$(curl -s "$API" \
      -H "content-type: application/json" \
      -H "authorization: $TOKEN_B" \
      --data-raw '{"action":"orders"}')
    echo "   Valid orders request response:"
    echo "$VALID_RESP" | jq '{status: .status, order_count: (.orders | length)}' 2>/dev/null || \
    echo "   $VALID_RESP" | head -1
    if echo "$VALID_RESP" | grep -qi "ok\|orders\|status"; then
        echo "   ✅ Valid requests still work after fix."
    else
        echo "   ⚠️  Valid request returned unexpected response."
    fi
else
    echo "   ℹ️  TOKEN_B not set — skipping valid request test."
fi

echo ""
echo "[TEST GROUP 3] CloudWatch should still log full error details..."

LOG_GROUP="/aws/lambda/DVSA-ORDER-MANAGER"
LATEST_STREAM=$(aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --order-by LastEventTime --descending --max-items 1 \
  --query 'logStreams[0].logStreamName' --output text \
  --region "$AWS_REGION" 2>/dev/null)

if [ -n "$LATEST_STREAM" ] && [ "$LATEST_STREAM" != "None" ]; then
    RECENT=$(aws logs get-log-events \
      --log-group-name "$LOG_GROUP" \
      --log-stream-name "$LATEST_STREAM" \
      --limit 15 --region "$AWS_REGION" \
      --query 'events[*].message' --output text 2>/dev/null)
    if echo "$RECENT" | grep -qiE "INTERNAL_ERROR|error|invalid"; then
        echo "   ✅ CloudWatch is receiving detailed internal logs."
    else
        echo "   ℹ️  No recent error logs found (may need to send a test request first)."
    fi
fi

echo ""
echo "=========================================="
echo " Results Summary:"
echo "   Inputs returning safe errors : $BLOCKED"
echo "   Inputs leaking internal info : $LEAKED"
echo ""
if [ "$LEAKED" -eq 0 ]; then
    echo "   ✅ FIXED: All malformed inputs return generic safe errors."
else
    echo "   ❌ $LEAKED inputs still leak internal details — fix not complete."
fi
echo "=========================================="
