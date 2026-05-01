// =============================================================
// LESSON 3 FIX: Enforce Ownership Check in Receipt Function
// Apply to: DVSA-ADMIN-GET-RECEIPT Lambda function
// File: get-receipt.js (or handler file in that Lambda)
// =============================================================
//
// ROOT CAUSE:
//   The DVSA-ADMIN-GET-RECEIPT function accepted any order-id
//   and generated a presigned S3 URL without verifying that
//   the requesting user owns that order.
//
// THE FIX:
//   Before generating a signed URL:
//   1. Extract the requesting user's identity from the JWT
//   2. Look up the order in DynamoDB
//   3. Compare order's userId with the token's sub/username
//   4. Reject if they don't match
// =============================================================

// -------------------------------------------------------
// BEFORE (VULNERABLE) — simplified pattern:
// -------------------------------------------------------
/*
exports.handler = async (event) => {
    const body = JSON.parse(event.body);
    const orderId = body["order-id"];              // ← no ownership check

    // Directly generate signed URL for any orderId
    const url = await generateSignedUrl(orderId);

    return {
        statusCode: 200,
        body: JSON.stringify({ url })
    };
};
*/

// -------------------------------------------------------
// AFTER (FIXED) — with ownership verification:
// -------------------------------------------------------

const AWS  = require('aws-sdk');
const jose = require('node-jose');       // already present in DVSA

const dynamodb = new AWS.DynamoDB.DocumentClient();
const s3       = new AWS.S3();

const ORDERS_TABLE  = process.env.orders_table  || 'DVSA-ORDERS-DB';
const RECEIPTS_BUCKET = process.env.receipts_bucket;
const REGION        = process.env.AWS_REGION   || 'us-east-1';

// ── Safe JWT decode (payload only, no signature verification needed
//    here since we only need identity for ownership check;
//    full verification should already happen in ORDER-MANAGER) ──
function decodeJwtPayload(token) {
    const raw = token.replace(/^Bearer\s+/i, '').trim();
    const [, payload] = raw.split('.');
    const padded = payload + '='.repeat((4 - payload.length % 4) % 4);
    return JSON.parse(Buffer.from(padded, 'base64url').toString('utf8'));
}

exports.handler = async (event) => {

    // ── 1. Parse request ──────────────────────────────────────
    let body;
    try {
        body = JSON.parse(event.body || '{}');
    } catch (_) {
        return resp(400, { status: 'err', msg: 'invalid request body' });
    }

    const orderId = body['order-id'];
    if (!orderId || typeof orderId !== 'string' || !/^[a-zA-Z0-9\-]{1,64}$/.test(orderId)) {
        return resp(400, { status: 'err', msg: 'invalid order-id' });
    }

    // ── 2. Extract requesting user identity from JWT ──────────
    const authHeader = (event.headers || {}).Authorization ||
                       (event.headers || {}).authorization || '';
    if (!authHeader) {
        return resp(401, { status: 'err', msg: 'missing authorization' });
    }

    let claims;
    try {
        claims = decodeJwtPayload(authHeader);
    } catch (_) {
        return resp(401, { status: 'err', msg: 'invalid token' });
    }

    const requestingUser = claims.sub || claims.username || claims['cognito:username'];
    if (!requestingUser) {
        return resp(401, { status: 'err', msg: 'cannot determine user identity' });
    }

    // ── 3. Look up the order in DynamoDB ──────────────────────
    let orderRecord;
    try {
        const result = await dynamodb.get({
            TableName: ORDERS_TABLE,
            Key: { 'order-id': orderId }
        }).promise();
        orderRecord = result.Item;
    } catch (e) {
        console.error('DynamoDB lookup failed:', e.message);
        return resp(500, { status: 'err', msg: 'order lookup failed' });
    }

    if (!orderRecord) {
        return resp(404, { status: 'err', msg: 'order not found' });
    }

    // ── 4. OWNERSHIP CHECK ────────────────────────────────────
    //    Compare the order's userId with the requesting user
    const orderOwner = orderRecord.userId || orderRecord.username || orderRecord.sub;

    if (!orderOwner || orderOwner !== requestingUser) {
        console.log(`ACCESS DENIED: user=${requestingUser} tried to access order owned by ${orderOwner}`);
        return resp(403, { status: 'err', msg: 'access denied' });
    }

    // ── 5. Generate presigned S3 URL only for the verified owner
    const s3Key = orderRecord.receiptKey || `${orderId}/receipt.pdf`;
    let signedUrl;
    try {
        signedUrl = s3.getSignedUrl('getObject', {
            Bucket:  RECEIPTS_BUCKET,
            Key:     s3Key,
            Expires: 300     // 5 minutes only — minimize exposure window
        });
    } catch (e) {
        console.error('S3 signed URL generation failed:', e.message);
        return resp(500, { status: 'err', msg: 'could not generate receipt URL' });
    }

    return resp(200, { status: 'ok', url: signedUrl });
};

function resp(statusCode, body) {
    return {
        statusCode,
        headers: { 'Access-Control-Allow-Origin': '*' },
        body: JSON.stringify(body)
    };
}
