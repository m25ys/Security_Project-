// =============================================================
// LESSON 2 FIX: JWT Signature Verification
// Full patch for DVSA-ORDER-MANAGER/order-manager.js
// Source: Based on the official Helper Guide provided
// =============================================================
//
// HOW TO APPLY:
// 1. Go to AWS Console → Lambda → DVSA-ORDER-MANAGER
// 2. Click Code tab
// 3. Open order-manager.js
// 4. Follow the 3 steps below
// 5. Click Deploy
// =============================================================

// -------------------------------------------------------
// STEP 1A: Add these helper functions AFTER the line:
//   const jose = require('node-jose');
// -------------------------------------------------------

const https = require('https');
let _jwksCache = { keystore: null, fetchedAt: 0 };

function resp(statusCode, bodyObj) {
    return {
        statusCode,
        headers: { "Access-Control-Allow-Origin": "*" },
        body: JSON.stringify(bodyObj)
    };
}

function fetchJson(url) {
    return new Promise((resolve, reject) => {
        https.get(url, (res) => {
            let data = "";
            res.on("data", (c) => data += c);
            res.on("end", () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try { resolve(JSON.parse(data)); } catch (e) { reject(e); }
                } else {
                    reject(new Error(`HTTP ${res.statusCode}: ${data.slice(0, 200)}`));
                }
            });
        }).on("error", reject);
    });
}

async function getCognitoKeystore() {
    const now = Date.now();
    // Cache keystore for 6 hours to avoid repeated fetches
    if (_jwksCache.keystore && (now - _jwksCache.fetchedAt) < 6 * 60 * 60 * 1000) {
        return _jwksCache.keystore;
    }
    const region = process.env.AWS_REGION;
    const userPoolId = process.env.userpoolid;
    const jwksUrl = `https://cognito-idp.${region}.amazonaws.com/${userPoolId}/.well-known/jwks.json`;
    const jwks = await fetchJson(jwksUrl);
    const keystore = await jose.JWK.asKeyStore(jwks);
    _jwksCache = { keystore, fetchedAt: now };
    return keystore;
}

async function verifyCognitoJwt(jwt) {
    const region = process.env.AWS_REGION;
    const userPoolId = process.env.userpoolid;
    const issuer = `https://cognito-idp.${region}.amazonaws.com/${userPoolId}`;

    const keystore = await getCognitoKeystore();

    // This will THROW if signature is invalid - that's what we want
    const result = await jose.JWS.createVerify(keystore).verify(jwt);
    const claims = JSON.parse(result.payload.toString("utf8"));

    // Validate standard claims
    if (claims.iss !== issuer) throw new Error("bad issuer");
    if (typeof claims.exp === "number" && (Date.now() / 1000) > claims.exp) {
        throw new Error("token expired");
    }
    if (claims.token_use && !["access", "id"].includes(claims.token_use)) {
        throw new Error("bad token_use");
    }

    return claims;
}

// -------------------------------------------------------
// STEP 1B: REPLACE the vulnerable JWT parsing block
// -------------------------------------------------------

// FIND and REMOVE this vulnerable block:
/*
var auth_header = headers.Authorization || headers.authorization;
var token_sections = auth_header.split('.');
var auth_data = jose.util.base64url.decode(token_sections[1]);
var token = JSON.parse(auth_data);
var user = token.username;
var isAdmin = false;
*/

// REPLACE WITH this verified block:
/*
var auth_header = (headers.Authorization || headers.authorization || "");
var jwt = auth_header.replace(/^Bearer\s+/i, "").trim();

if (!jwt) {
    return callback(null, resp(401, { status: "err", msg: "missing authorization" }));
}

verifyCognitoJwt(jwt).then((claims) => {
    var user = claims.username || claims["cognito:username"] || claims.sub;
    if (!user) {
        return callback(null, resp(401, { status: "err", msg: "missing subject" }));
    }
    var isAdmin = false;

    // ... rest of your existing handler logic goes here ...

*/

// -------------------------------------------------------
// STEP 1C: ADD this catch block at the END of the handler
// Just before the final closing brace
// -------------------------------------------------------

/*
}).catch((e) => {
    console.log("JWT verify failed:", e.message || e);
    return callback(null, resp(401, { status: "err", msg: "invalid token" }));
});
*/

// -------------------------------------------------------
// FULL EXAMPLE of what the patched handler opening looks like:
// -------------------------------------------------------

/*
exports.handler = function(event, context, callback) {
    var headers = event.headers || {};
    var body = JSON.parse(event.body || "{}");

    var auth_header = (headers.Authorization || headers.authorization || "");
    var jwt = auth_header.replace(/^Bearer\s+/i, "").trim();

    if (!jwt) {
        return callback(null, resp(401, { status: "err", msg: "missing authorization" }));
    }

    verifyCognitoJwt(jwt).then((claims) => {
        var user = claims.username || claims["cognito:username"] || claims.sub;
        if (!user) {
            return callback(null, resp(401, { status: "err", msg: "missing subject" }));
        }
        var isAdmin = false;

        // --- YOUR EXISTING ACTION HANDLING LOGIC STAYS HERE ---
        var action = body.action;

        if (action === "orders") {
            // fetch orders for user ...
        }
        // ... etc

    }).catch((e) => {
        console.log("JWT verify failed:", e.message || e);
        return callback(null, resp(401, { status: "err", msg: "invalid token" }));
    });
};
*/
