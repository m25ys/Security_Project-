#!/bin/bash
# =============================================================
# SHARED HELPER: Generate Tables A and B scaffolds for Part 9
# Usage: bash helpers/generate_tables.sh <lesson_number>
#   Prints pre-filled markdown tables for the report
# =============================================================

LESSON="${1:-ALL}"

print_tables() {
    local NUM="$1"
    local TITLE="$2"
    local RULE="$3"
    local ARTIFACTS="$4"
    local NORMAL="$5"
    local EXPLOIT="$6"
    local DEVIATION="$7"
    local CLASS="$8"
    local FIX="$9"
    local POSTFIX="${10}"

    echo ""
    echo "================================================================"
    echo " LESSON #${NUM}: ${TITLE} — Part 9 Table Scaffold"
    echo "================================================================"
    echo ""
    echo "TABLE A:"
    echo "| Vulnerability | Intended Rule(s) | Artifacts Used | Normal Behavior Evidence | Exploit Behavior Evidence |"
    echo "|---|---|---|---|---|"
    echo "| ${TITLE} | ${RULE} | ${ARTIFACTS} | ${NORMAL} | ${EXPLOIT} |"
    echo ""
    echo "TABLE B:"
    echo "| Vulnerability | Why This Is a Deviation | Deviation Class | Fix Applied (Where) | Post-Fix Verification | Optional Latency |"
    echo "|---|---|---|---|---|---|"
    echo "| ${TITLE} | ${DEVIATION} | ${CLASS} | ${FIX} | ${POSTFIX} | Measure before/after ms |"
    echo ""
}

case "$LESSON" in
  1|"L1")
    print_tables "1" "Event Injection" \
      "Backend must never execute attacker-controlled input; all request bodies must be treated as plain data." \
      "API POST /order request; CloudWatch /aws/lambda/DVSA-ORDER-MANAGER logs; node-serialize source code; exploit curl command output." \
      "Normal POST with valid JSON action returns expected order response; no code execution occurs." \
      "Payload containing _\$\$ND_FUNC\$\$_ marker triggers file write to /tmp and logs 'FILE READ SUCCESS' in CloudWatch." \
      "The backend deserializes user input as executable JavaScript instead of plain data, violating the rule that input must never be executed." \
      "Intentional misuse / security-relevant abuse" \
      "Remove node-serialize from DVSA-ORDER-MANAGER; replace with JSON.parse + action allowlist validation." \
      "Re-sending the RCE payload returns 400/error with no FILE READ line in CloudWatch logs."
    ;;
  2|"L2")
    print_tables "2" "Broken Authentication" \
      "Only a valid, cryptographically verified JWT may determine user identity; User B must not access User C's orders." \
      "Browser login flow; captured /order API request; JWT header.payload.signature structure; decoded payload claims; exploit curl response; order-manager.js source." \
      "TOKEN_B returns only User B's orders when calling action:orders." \
      "Forged token (payload edited to set username/sub = victim, original signature retained) returns User C's full order list." \
      "Backend trusted identity claims from an unverified JWT payload. Signature was not checked, so attacker-controlled claims authorized access to another user's data." \
      "Intentional misuse / security-relevant abuse" \
      "verifyCognitoJwt() added to order-manager.js; fetches JWKS, verifies signature, checks iss/exp/token_use before trusting any claim." \
      "Forged token returns 401 'invalid token'; legitimate TOKEN_B still returns User B's own orders only."
    ;;
  3|"L3")
    print_tables "3" "Sensitive Information Disclosure" \
      "Only the authenticated order owner may obtain a receipt download link; admin receipt functions must verify ownership before generating signed S3 URLs." \
      "DVSA browser receipt flow; API /order endpoint; DVSA-ADMIN-GET-RECEIPT Lambda source; CloudWatch logs; S3 signed URL response." \
      "User B requesting a receipt for their own order receives a signed S3 URL for their own receipt only." \
      "User B sending User C's order-id to the get-receipt action receives a valid signed S3 URL for User C's receipt, allowing unauthorized download." \
      "The admin receipt function did not verify that the requesting user owns the supplied order-id before generating a signed URL." \
      "Intentional misuse / security-relevant abuse" \
      "Added ownership check in DVSA-ADMIN-GET-RECEIPT: query order from DynamoDB, compare order's userId with token's sub before generating URL." \
      "Request with User C's order-id using User B's token returns 403 Forbidden; User B can still retrieve their own receipt normally."
    ;;
  4|"L4")
    print_tables "4" "Insecure Cloud Configuration" \
      "Only authenticated, authorized users may write to the DVSA S3 bucket; uploaded files must be validated before downstream processing." \
      "S3 bucket ACL; bucket policy; public access block settings; S3 event notification config; CloudWatch Lambda trigger logs." \
      "Authenticated users can only upload receipts through the intended application flow; direct unauthenticated S3 writes are blocked." \
      "Unauthenticated PUT to the receipts bucket succeeds (--no-sign-request), and the uploaded object triggers the Lambda function." \
      "S3 bucket lacked Block Public Access and had an overly permissive bucket policy allowing unauthenticated writes, creating an uncontrolled Lambda trigger surface." \
      "Accidental misconfiguration" \
      "Enabled S3 Block Public Access on receipts bucket; restricted bucket policy to allow writes only from authorized Lambda execution roles; added object key prefix validation in Lambda trigger." \
      "Unauthenticated upload now returns 403 AccessDenied; authenticated application flow still works normally."
    ;;
  5|"L5")
    print_tables "5" "Broken Access Control" \
      "Only the internal billing workflow may invoke DVSA-ADMIN-UPDATE-ORDERS; normal users must not be able to change order status to paid without completing payment." \
      "DVSA order flow (new→shipping→billing→paid); API /order endpoint; DVSA-ADMIN-UPDATE-ORDERS Lambda; CloudWatch order status logs; DynamoDB order record before/after." \
      "Normal billing flow: order status progresses new→shipped→paid only after real billing completes." \
      "Attacker sends billing payload with manipulated parameters; DVSA-ADMIN-UPDATE-ORDERS is invoked internally and marks order as paid without actual payment processing." \
      "The public-facing billing Lambda invoked the privileged admin update function without checking caller authorization, allowing unprivileged users to trigger a privileged state change." \
      "Intentional misuse / security-relevant abuse" \
      "Added authorization check in billing Lambda: verify request originates from internal billing workflow before invoking DVSA-ADMIN-UPDATE-ORDERS; validate state transition server-side." \
      "Exploit attempt no longer changes order status to paid; legitimate billing flow still correctly marks orders as paid after payment processing."
    ;;
  6|"L6")
    print_tables "6" "Denial of Service" \
      "The billing endpoint must remain available to all legitimate users; no single client should be able to exhaust Lambda concurrency for the billing path." \
      "Concurrent curl requests; API response codes; Lambda concurrency metrics in CloudWatch; response time measurements before/after flood." \
      "Single billing request completes in normal baseline time with 200 response." \
      "50 concurrent billing requests saturate Lambda reserved concurrency; subsequent legitimate requests receive 429 TooManyRequestsException or greatly increased latency." \
      "No per-user rate limiting or concurrency reservation was enforced on the billing endpoint, allowing a single attacker to exhaust the shared Lambda pool." \
      "Intentional misuse / security-relevant abuse" \
      "Applied API Gateway usage plan with per-IP rate limit and burst limit on billing endpoint; added Lambda reserved concurrency reservation to isolate billing path." \
      "After rate limiting: flood of 50 requests receives 429 responses after threshold; single legitimate request still completes normally within baseline time."
    ;;
  7|"L7")
    print_tables "7" "Over-Privileged Functions" \
      "Lambda execution roles must follow least privilege; DVSA-SEND-RECEIPT-EMAIL must only access its specific receipts bucket and DVSA tables, not all S3 buckets or all DynamoDB tables." \
      "IAM role attached policies; IAM Policy Simulator results; CloudTrail activity log; generated least-privilege policy from Access Advisor." \
      "Function performs only: S3 GetObject on receipts bucket, SES SendEmail, DynamoDB GetItem on DVSA tables." \
      "IAM Policy Simulator shows s3:GetObject/PutObject on arbitrary buckets ALLOWED; dynamodb:Scan/PutItem/DeleteItem on any table ALLOWED — far beyond receipt sending purpose." \
      "The execution role used wildcard resource ARNs (arn:aws:s3:::*) and AmazonSESFullAccess. Any compromise of the function would grant blast-radius access to all S3 and DynamoDB resources in the account." \
      "Accidental misconfiguration" \
      "Detached AmazonSESFullAccess; replaced inline policies with least-privilege policy scoped to specific receipts bucket ARN and specific DVSA table ARNs only." \
      "IAM Policy Simulator now returns DENIED for s3:GetObject on arbitrary buckets and dynamodb:Scan on non-DVSA tables; receipt email flow still works."
    ;;
  8|"L8")
    print_tables "8" "Logic Vulnerabilities" \
      "Order quantity must be locked once billing begins; the total charged must always equal the value of items at billing time, not at order completion time." \
      "Concurrent curl requests (billing + update); order record in DynamoDB before/after; CloudWatch Lambda processing logs showing request ordering; final order state (items vs total)." \
      "Sequential billing then update: billing locks the order state; subsequent update request is rejected because order is already in billing state." \
      "Concurrent billing (1 item, \$25) + update (5 items) race: update processes before billing locks state; final order shows 5 items but total charged is \$25." \
      "No server-side locking or conditional write prevented order modification during an in-flight billing operation. The update Lambda could overwrite order state after billing had read but before it had written." \
      "Intentional misuse / security-relevant abuse" \
      "Added DynamoDB conditional update expression in billing Lambda: ConditionExpression='#status = :expected_status' to atomically lock order state at billing start; update Lambda checks status before allowing modification." \
      "Race condition attempt: billing still charges \$25, but final item count remains 1 because the update request is rejected with ConditionalCheckFailedException."
    ;;
  9|"L9")
    print_tables "9" "Vulnerable Dependencies" \
      "Lambda deployment packages must not include libraries with known RCE vulnerabilities; dependencies must be pinned to reviewed, safe versions." \
      "node-serialize package version (0.0.4); npm audit output; CVE database entry for node-serialize; package.json in Lambda deployment; CloudWatch RCE proof from Lesson 1." \
      "Normal request processing uses safe JSON.parse; no deserialization of functions occurs." \
      "node-serialize 0.0.4 deserializes the _\$\$ND_FUNC\$\$_ marker as executable JavaScript, proven by FILE READ SUCCESS in CloudWatch (shared with Lesson 1 exploit)." \
      "node-serialize 0.0.4 contains a known deserialization RCE vulnerability (no CVE assigned but widely documented). Including it in the Lambda deployment package created an RCE entry point accessible to any caller." \
      "Intentional misuse / security-relevant abuse" \
      "Removed node-serialize from package.json; replaced with safe JSON.parse; ran npm audit to confirm no remaining high-severity vulnerabilities; redeployed Lambda zip." \
      "npm audit on updated package returns 0 high/critical findings; RCE payload no longer produces FILE READ SUCCESS in CloudWatch."
    ;;
  10|"L10")
    print_tables "10" "Unhandled Exceptions" \
      "Backend must never expose stack traces, file paths, or internal error details to API clients; all exceptions must be caught centrally and return only generic client-safe messages." \
      "Malformed curl requests (empty body, null fields, wrong types, path traversal); API response bodies; CloudWatch Lambda error logs; HTTP status codes returned." \
      "Valid requests return expected JSON responses; invalid requests return a generic error message with no internal details." \
      "Malformed requests cause Lambda crashes that leak stack traces, internal file paths (/var/task/), or error messages revealing backend structure in the API response body." \
      "Exceptions from JSON parsing and missing field access were not caught at the handler level, causing raw Node.js/Python error objects to propagate through API Gateway to the client." \
      "Accidental misconfiguration" \
      "Added try/catch wrapper around entire handler body; added input validation before processing; safeError() helper logs full details to CloudWatch only, returns generic message to client." \
      "Malformed requests now return generic 400/500 response with no stack trace; CloudWatch still receives full error details; valid requests continue to work normally."
    ;;
  "ALL")
    for L in 1 2 3 4 5 6 7 8 9 10; do
        bash "$0" "$L"
    done
    ;;
  *)
    echo "Usage: bash helpers/generate_tables.sh <1-10|ALL>"
    exit 1
    ;;
esac
