// Cloudflare Worker: sends an FCM push notification to every member of a
// group (except the sender) whenever the Flutter app calls this endpoint.
//
// Why this exists: Firebase Cloud Functions requires the Blaze (billing)
// plan. Cloudflare Workers has a genuinely free tier with no card required,
// so instead of triggering off a Firestore write (which needs Cloud
// Functions), the app calls this endpoint directly right after it writes
// the message to Firestore.

async function getAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);

  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: env.CLIENT_EMAIL,
    scope:
      "https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore.readonly",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const b64url = (obj) =>
    btoa(JSON.stringify(obj))
      .replace(/=+$/, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");

  const unsigned = `${b64url(header)}.${b64url(claims)}`;

  const key = await importPrivateKey(env.PRIVATE_KEY);
  const signatureBuf = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(unsigned)
  );

  const jwt = `${unsigned}.${arrayBufferToBase64Url(signatureBuf)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const data = await res.json();

  if (!data.access_token) {
    throw new Error("Failed to get access token: " + JSON.stringify(data));
  }

  return data.access_token;
}

async function importPrivateKey(pem) {
  const pemContents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");

  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  return crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
}

function arrayBufferToBase64Url(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  bytes.forEach((b) => (binary += String.fromCharCode(b)));
  return btoa(binary).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

async function firestoreGet(env, accessToken, path) {
  const url = `https://firestore.googleapis.com/v1/projects/${env.PROJECT_ID}/databases/(default)/documents/${path}`;

  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!res.ok) return null;

  return res.json();
}

// Firestore's REST API returns typed fields like { stringValue: "..." } or
// { arrayValue: { values: [...] } } instead of plain JSON values.
function fieldValue(fields, key) {
  const f = fields?.[key];
  if (!f) return undefined;

  if ("stringValue" in f) return f.stringValue;
  if ("booleanValue" in f) return f.booleanValue;
  if ("arrayValue" in f) {
    return (f.arrayValue.values || []).map((v) => v.stringValue);
  }

  return undefined;
}

async function sendFcm(env, accessToken, token, title, body, data) {
  const url = `https://fcm.googleapis.com/v1/projects/${env.PROJECT_ID}/messages:send`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
        android: {
          priority: "HIGH",
          notification: { sound: "notification_sound" },
        },
        apns: {
          payload: { aps: { sound: "notification_sound.wav" } },
        },
      },
    }),
  });

  return res.json();
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    // Simple shared-secret check so random people can't spam your endpoint
    // and burn your free-tier quota. Not a substitute for real auth, but
    // fine for a small app — the worst case is someone can trigger your
    // own notifications, not read/write your data.
    if (request.headers.get("x-app-secret") !== env.APP_SECRET) {
      return new Response("Unauthorized", { status: 401 });
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return new Response("Invalid JSON", { status: 400 });
    }

    const { groupId, senderPhone, text, type } = body;

    if (!groupId || !senderPhone || !text) {
      return new Response("Missing groupId, senderPhone, or text", {
        status: 400,
      });
    }

    try {
      const accessToken = await getAccessToken(env);

      const groupDoc = await firestoreGet(env, accessToken, `groups/${groupId}`);
      if (!groupDoc) {
        return new Response("Group not found", { status: 404 });
      }

      const members = fieldValue(groupDoc.fields, "members") || [];
      const groupName = fieldValue(groupDoc.fields, "name") || "Group";

      const recipients = members.filter((phone) => phone !== senderPhone);

      const results = [];

      for (const phone of recipients) {
        const userDoc = await firestoreGet(env, accessToken, `users/${phone}`);
        if (!userDoc) continue;

        const fcmToken = fieldValue(userDoc.fields, "fcmToken");
        if (!fcmToken) continue;

        const title = type === "announcement" ? `📢 ${groupName}` : groupName;

        const result = await sendFcm(env, accessToken, fcmToken, title, text, {
          groupId,
          groupName,
        });

        results.push({ phone, result });
      }

      return new Response(JSON.stringify({ sent: results.length, results }), {
        headers: { "Content-Type": "application/json" },
      });
    } catch (err) {
      return new Response("Error: " + err.message, { status: 500 });
    }
  },
};
