#!/bin/bash
# =============================================================
# DVSA PROJECT - ENVIRONMENT CONFIGURATION
# Fill in your values before running any lesson script
# =============================================================

# --- YOUR API GATEWAY URL ---
# Found in AWS Console → API Gateway → Stages → Invoke URL
# Example: https://abc123xyz.execute-api.us-east-1.amazonaws.com/Stage
export API_URL="https://YOUR_API_ID.execute-api.us-east-1.amazonaws.com/Stage"

# Append /order for most lessons
export API="${API_URL}/order"

# --- YOUR DVSA WEBSITE URL ---
# Found in CloudFormation → Outputs → WebsiteURL
export WEBSITE_URL="http://YOUR_BUCKET_NAME.s3-website-us-east-1.amazonaws.com"

# --- AWS REGION ---
export AWS_REGION="us-east-1"

# --- YOUR AWS ACCOUNT ID ---
# Found in AWS Console → top-right account dropdown
export ACCOUNT_ID="YOUR_12_DIGIT_ACCOUNT_ID"

# --- S3 RECEIPTS BUCKET NAME ---
# Found in S3 console, look for a bucket with "receipt" in the name
export RECEIPTS_BUCKET="YOUR_RECEIPTS_BUCKET_NAME"

# --- USER TOKENS (captured from browser DevTools → Network tab) ---
# Log in as each user, go to Orders page, capture the Authorization header
export TOKEN_A="PASTE_USER_A_JWT_TOKEN_HERE"   # Admin user (if needed)
export TOKEN_B="PASTE_USER_B_JWT_TOKEN_HERE"   # Attacker user
export TOKEN_C="PASTE_USER_C_JWT_TOKEN_HERE"   # Victim user

# --- COGNITO USER POOL ID ---
# Found in AWS Console → Cognito → User Pools
export USER_POOL_ID="us-east-1_XXXXXXXXX"

echo "✅ Config loaded."
echo "   API endpoint : $API"
echo "   Website URL  : $WEBSITE_URL"
echo "   Region       : $AWS_REGION"
