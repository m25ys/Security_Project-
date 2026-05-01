#!/bin/bash
# =============================================================
# DVSA PROJECT - ENVIRONMENT CONFIGURATION
# Loads values from ../.env — edit that file, not this one.
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "❌ .env file not found at: $ENV_FILE"
    echo "   Create it by copying the template from the project root."
    exit 1
fi

# Load and export all variables from .env (skips comment/blank lines)
set -a
# shellcheck source=../.env
source "$ENV_FILE"
set +a

# Derived values
export API="${API_URL}/order"

# Validate that the 5 required TODOs have been filled in
MISSING=()
[ "$API_URL"        = "https://YOUR_API_ID.execute-api.us-east-1.amazonaws.com/Stage" ] && MISSING+=("API_URL")
[ "$ACCOUNT_ID"     = "YOUR_12_DIGIT_ACCOUNT_ID" ]  && MISSING+=("ACCOUNT_ID")
[ "$USER_POOL_ID"   = "us-east-1_XXXXXXXXX" ]        && MISSING+=("USER_POOL_ID")
[ "$RECEIPTS_BUCKET" = "YOUR_RECEIPTS_BUCKET_NAME" ] && MISSING+=("RECEIPTS_BUCKET")
[ "$WEBSITE_URL"    = "http://YOUR_BUCKET_NAME.s3-website-us-east-1.amazonaws.com" ] && MISSING+=("WEBSITE_URL")
[ "$TOKEN_B"        = "PASTE_USER_B_JWT_TOKEN_HERE" ] && MISSING+=("TOKEN_B")
[ "$TOKEN_C"        = "PASTE_USER_C_JWT_TOKEN_HERE" ] && MISSING+=("TOKEN_C")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "⚠️  The following values in .env still need to be filled in:"
    for VAR in "${MISSING[@]}"; do
        echo "   - $VAR"
    done
    echo ""
fi

echo "✅ Config loaded."
echo "   API endpoint : $API"
echo "   Website URL  : $WEBSITE_URL"
echo "   Region       : $AWS_REGION"
echo "   Account ID   : $ACCOUNT_ID"
