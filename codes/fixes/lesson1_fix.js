// =============================================================
// LESSON 1 & 9 FIX: Remove node-serialize / Safe Input Handling
// Apply this patch to the DVSA-ORDER-MANAGER Lambda function
// =============================================================
//
// HOW TO APPLY:
// 1. Go to AWS Console → Lambda → DVSA-ORDER-MANAGER
// 2. Open the Code tab
// 3. Find order-manager.js
// 4. Apply the changes described below
// 5. Click Deploy
//
// =============================================================

// -------------------------------------------------------
// BEFORE (VULNERABLE): Uses node-serialize to parse body
// -------------------------------------------------------
/*
const serialize = require('node-serialize');

exports.handler = function(event, context, callback) {
    var body = serialize.unserialize(event.body);   // ← DANGEROUS
    var action = body.action;
    ...
}
*/

// -------------------------------------------------------
// AFTER (FIXED): Use safe JSON.parse with input allowlist
// -------------------------------------------------------

// At the top of order-manager.js, REMOVE this line:
//   const serialize = require('node-serialize');
//
// REPLACE the body parsing block with:

/*
exports.handler = function(event, context, callback) {

    // SAFE: Use standard JSON.parse instead of node-serialize
    var body;
    try {
        body = JSON.parse(event.body);
    } catch (e) {
        return callback(null, {
            statusCode: 400,
            headers: { "Access-Control-Allow-Origin": "*" },
            body: JSON.stringify({ status: "err", msg: "invalid request body" })
        });
    }

    // SAFE: Validate action against an explicit allowlist
    const ALLOWED_ACTIONS = ["new", "get", "orders", "shipping", "billing", "cancel"];
    var action = body.action;

    if (!action || !ALLOWED_ACTIONS.includes(action)) {
        return callback(null, {
            statusCode: 400,
            headers: { "Access-Control-Allow-Origin": "*" },
            body: JSON.stringify({ status: "err", msg: "invalid action" })
        });
    }

    // SAFE: Validate cart-id is a plain string, no special characters
    if (body["cart-id"] && !/^[a-zA-Z0-9_\-]{0,64}$/.test(body["cart-id"])) {
        return callback(null, {
            statusCode: 400,
            headers: { "Access-Control-Allow-Origin": "*" },
            body: JSON.stringify({ status: "err", msg: "invalid cart-id" })
        });
    }

    // ... rest of handler continues normally
};
*/

// -------------------------------------------------------
// ALSO: Remove node-serialize from package.json
// -------------------------------------------------------
/*
In package.json, find and REMOVE:
    "node-serialize": "0.0.4"

Then in your Lambda deployment package, run:
    npm install

And redeploy the zip.
*/

console.log("This file is documentation only - apply changes manually in AWS Console.");
