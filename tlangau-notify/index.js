export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

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
      return new Response("Missing fields", { status: 400 });
    }

    try {
      const accessToken = await getAccessToken(env);

      const groupDoc = await firestoreGet(
        env,
        accessToken,
        `groups/${groupId}`
      );

      if (!groupDoc) {
        return new Response(
          JSON.stringify({
            error: "Group not found",
            debug: {
              project: env.PROJECT_ID,
              path: `groups/${groupId}`,
            },
          }),
          { status: 404 }
        );
      }

      const members = fieldValue(groupDoc.fields, "members") || [];
      const groupName =
        fieldValue(groupDoc.fields, "name") || "Group";

      const recipients = members.filter(
        (p) => p !== senderPhone
      );

      const results = await Promise.all(
        recipients.map(async (phone) => {
          const userDoc = await firestoreGet(
            env,
            accessToken,
            `users/${phone}`
          );

          if (!userDoc) return null;

          const fcmToken = fieldValue(
            userDoc.fields,
            "fcmToken"
          );

          if (!fcmToken) return null;

          const title =
            type === "announcement"
              ? `📢 ${groupName}`
              : groupName;

          const result = await sendFcm(
            env,
            accessToken,
            fcmToken,
            title,
            text,
            { groupId, groupName }
          );

          return { phone, result };
        })
      );

      return new Response(
        JSON.stringify({
          sent: results.filter(Boolean).length,
          results: results.filter(Boolean),
        }),
        {
          headers: { "Content-Type": "application/json" },
        }
      );
    } catch (err) {
      return new Response(
        JSON.stringify({
          error: err.message,
        }),
        { status: 500 }
      );
    }
  },
};
async function getAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);

  const header = { alg: "RS256", typ: "JWT" };

  const claims = {
    iss: env.CLIENT_EMAIL,
    scope:
      "https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const base64Url = (obj) =>
    btoa(JSON.stringify(obj))
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");

  const unsignedJWT =
    base64Url(header) + "." + base64Url(claims);

  const key = await importPrivateKey(env.PRIVATE_KEY);

  const signature = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(unsignedJWT)
  );

  const jwt =
    unsignedJWT +
    "." +
    arrayBufferToBase64Url(signature);

  const res = await fetch(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body:
        "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=" +
        jwt,
    }
  );

  const data = await res.json();

  if (!data.access_token) {
    throw new Error(JSON.stringify(data));
  }

  return data.access_token;
}
async function firestoreGet(env, accessToken, path) {
  const url = `https://firestore.googleapis.com/v1/projects/${env.PROJECT_ID}/databases/(default)/documents/${path}`;

  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!res.ok) {
    console.log("Firestore error:", await res.text());
    return null;
  }

  return res.json();
}
function fieldValue(fields, key) {
  const f = fields?.[key];
  if (!f) return undefined;

  if (f.stringValue) return f.stringValue;
  if (f.booleanValue !== undefined) return f.booleanValue;

  if (f.arrayValue) {
    return (f.arrayValue.values || []).map(
      (v) => v.stringValue
    );
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
      },
    }),
  });

  return res.json();
}
async function importPrivateKey(pem) {
  pem = pem.replace(/\\n/g, "\n").trim();

  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const binary = Uint8Array.from(atob(base64), (c) =>
    c.charCodeAt(0)
  );

  return crypto.subtle.importKey(
    "pkcs8",
    binary.buffer,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"]
  );
}

function arrayBufferToBase64Url(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";

  for (let b of bytes) {
    binary += String.fromCharCode(b);
  }

  return btoa(binary)
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}