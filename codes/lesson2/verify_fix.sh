#!/bin/bash
# =============================================================
# LESSON 2: FIX VERIFICATION
# After applying the JWT signature verification fix,
# confirm the forged token is now rejected
# =============================================================

source "$(dirname "$0")/../config.sh"

echo "=========================================="
echo " LESSON 2: Broken Authentication - Fix Verification"
echo "=========================================="

# Rebuild the forged token
export VICTIM_USER=$(python3 - <<'PY'
import os, json, base64
token = os.environ.get("TOKEN_C", "")
if not token or "PASTE" in token:
    print("UNKNOWN")
else:
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    data = json.loads(base64.urlsafe_b64decode(payload.encode()))
    print(data.get("username") or data.get("sub") or "UNKNOWN")
PY
)

export FAKE_AS_C="$(python3 - <<'PY'
import os, json, base64
token_b = os.environ.get("TOKEN_B", "")
victim  = os.environ.get("VICTIM_USER", "")
if not token_b or not victim or "PASTE" in token_b:
    print("")
else:
    h, p, s = token_b.split(".")
    p += "=" * (-len(p) % 4)
    data = json.loads(base64.urlsafe_b64decode(p.encode()))
    data["username"] = victim
    data["sub"]      = victim
    new_p = base64.urlsafe_b64encode(
        json.dumps(data, separators=(",", ":")).encode()
    ).rstrip(b"=").decode()
    print(f"{h}.{new_p}.{s}")
PY
)"

# -------------------------------------------------------
# TEST 1: Forged token should now be rejected
# -------------------------------------------------------
echo ""
echo "[TEST 1] Forged token request (should be REJECTED after fix)..."
FORGED_RESPONSE=$(curl -s "$API" \
  -H "content-type: application/json" \
  -H "authorization: $FAKE_AS_C" \
  --data-raw '{"action":"orders"}')

echo "   Response: $FORGED_RESPONSE"

if echo "$FORGED_RESPONSE" | grep -qi "invalid token\|unauthorized\|401\|err"; then
    echo "   ✅ FIXED: Forged token was rejected!"
else
    echo "   ❌ Fix may not be applied yet - check the Lambda code."
fi

# -------------------------------------------------------
# TEST 2: Legitimate token should still work
# -------------------------------------------------------
echo ""
echo "[TEST 2] Legitimate token for User B (should still WORK)..."
LEGIT_RESPONSE=$(curl -s "$API" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_B" \
  --data-raw '{"action":"orders"}')

echo "   Response: $LEGIT_RESPONSE"

if echo "$LEGIT_RESPONSE" | grep -qi "ok\|orders\|status"; then
    echo "   ✅ Legitimate access still works correctly."
else
    echo "   ⚠️  Unexpected response - check if fix broke normal functionality."
fi

echo ""
echo "=========================================="
echo " Lesson 2 fix verification complete."
echo "=========================================="
