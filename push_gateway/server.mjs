import http from "node:http";
import http2 from "node:http2";
import crypto from "node:crypto";
import fs from "node:fs";

const port = Number(process.env.PORT || 8080);
const secret = process.env.PUSH_GATEWAY_SECRET || "";
const keyID = process.env.APNS_KEY_ID || "";
const teamID = process.env.APNS_TEAM_ID || "";
const topic = process.env.APNS_TOPIC || "com.hyse.HyseApp";
const keyPath = process.env.APNS_KEY_PATH || "/run/secrets/apns_key.p8";
let cachedJWT = null;
let cachedJWTAt = 0;

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

function providerToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWTAt < 45 * 60) return cachedJWT;
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyID }));
  const claims = base64url(JSON.stringify({ iss: teamID, iat: now }));
  const unsigned = `${header}.${claims}`;
  const signature = crypto.sign("sha256", Buffer.from(unsigned), {
    key: fs.readFileSync(keyPath),
    dsaEncoding: "ieee-p1363"
  }).toString("base64url");
  cachedJWT = `${unsigned}.${signature}`;
  cachedJWTAt = now;
  return cachedJWT;
}

async function sendOne(device, message) {
  const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const client = http2.connect(`https://${host}`);
  return await new Promise((resolve) => {
    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${device.token}`,
      authorization: `bearer ${providerToken()}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10"
    });
    let responseBody = "";
    request.setEncoding("utf8");
    request.on("response", (headers) => {
      request.on("data", (chunk) => { responseBody += chunk; });
      request.on("end", () => { client.close(); resolve({ token: device.token, status: Number(headers[":status"] || 0), response: responseBody }); });
    });
    request.on("error", (error) => { client.destroy(); resolve({ token: device.token, status: 0, response: error.message }); });
    request.end(JSON.stringify({
      aps: { alert: { title: message.title, body: message.body }, sound: "default" },
      type: message.type || "hyse_notification",
      community_id: message.community_id,
      post_id: message.post_id,
      workout_id: message.workout_id
    }));
  });
}

const server = http.createServer(async (request, response) => {
  if (request.method === "GET" && request.url === "/health") {
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify({ status: "ok", configured: !!(secret && keyID && teamID && fs.existsSync(keyPath)) }));
    return;
  }
  if (request.method !== "POST" || request.url !== "/send" || request.headers["x-hyse-push-secret"] !== secret || !secret) {
    response.writeHead(404); response.end(); return;
  }
  let raw = "";
  for await (const chunk of request) {
    raw += chunk;
    if (raw.length > 256_000) { response.writeHead(413); response.end(); return; }
  }
  try {
    if (!keyID || !teamID || !fs.existsSync(keyPath)) throw new Error("APNs credentials are not configured")
    const message = JSON.parse(raw);
    const devices = Array.isArray(message.devices) ? message.devices.slice(0, 500) : [];
    const results = [];
    for (let index = 0; index < devices.length; index += 25) {
      results.push(...await Promise.all(devices.slice(index, index + 25).map((device) => sendOne(device, message))));
    }
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify({ sent: results.filter((item) => item.status === 200).length, results }));
  } catch (error) {
    response.writeHead(503, { "content-type": "application/json" });
    response.end(JSON.stringify({ error: error.message }));
  }
});

server.listen(port, "0.0.0.0");
