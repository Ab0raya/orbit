/**
 * Orbit Integration Test Client
 *
 * Verifies end-to-end WebSocket communication protocol:
 * 1. Connects to ws://127.0.0.1:4371
 * 2. Receives welcome event
 * 3. Sends ping -> receives response with timestamp
 * 4. Tests unauthorized request -> receives UNAUTHORIZED
 * 5. Tests invalid pairing code -> receives INVALID_PAIRING_CODE
 * 6. Sends valid pairing.verify -> receives success & device.paired event
 * 7. Sends agent.status as paired client -> receives real agent telemetry
 * 8. Sends system.info as paired client -> receives host hardware specs
 * 9. Disconnects cleanly
 */

const WS_URL = process.env.ORBIT_WS_URL || "ws://127.0.0.1:4371";
const PAIRING_CODE = process.env.ORBIT_TEST_PAIRING_CODE || "842917";

console.log(`[Test Client] Connecting to Orbit Desktop Agent at ${WS_URL}...`);

const ws = new WebSocket(WS_URL);

let step = 0;
let pendingId = null;

function sendRequest(id, action, payload = {}) {
  const req = {
    id,
    type: "request",
    action,
    payload,
  };
  pendingId = id;
  console.log(`[Test Client] -> Sent request: [${action}] (id: ${id})`);
  ws.send(JSON.stringify(req));
}

ws.onopen = () => {
  console.log("[Test Client] Socket connected successfully.");
};

ws.onmessage = (event) => {
  const raw = event.data.toString();
  const msg = JSON.parse(raw);
  console.log(`[Test Client] <- Received: type="${msg.type}"`, msg.action ? `action="${msg.action}"` : `event="${msg.event}"`);

  // Step 1: Handle Welcome Event
  if (msg.type === "event" && msg.event === "welcome") {
    console.log("  [Step 1 PASS] Received welcome event:", JSON.stringify(msg.payload));
    // Step 2: Send Ping
    step = 2;
    sendRequest("req_ping_1", "ping", {});
    return;
  }

  // Step 2: Handle Ping Response
  if (step === 2 && msg.id === "req_ping_1") {
    if (!msg.success || !msg.payload?.timestamp) {
      throw new Error(`Ping failed: ${JSON.stringify(msg)}`);
    }
    console.log("  [Step 2 PASS] Received ping response with timestamp:", msg.payload.timestamp);

    // Step 3: Test Unpaired Authorization Check
    step = 3;
    console.log("[Test Client] Testing authorization enforcement on unpaired session...");
    sendRequest("req_unpaired_sys", "system.info", {});
    return;
  }

  // Step 3: Handle Unpaired Response (Must be UNAUTHORIZED)
  if (step === 3 && msg.id === "req_unpaired_sys") {
    if (msg.success || msg.error?.code !== "UNAUTHORIZED") {
      throw new Error(`Expected UNAUTHORIZED error, got: ${JSON.stringify(msg)}`);
    }
    console.log("  [Step 3 PASS] Unpaired system.info properly rejected with UNAUTHORIZED.");

    // Step 4: Test Invalid Pairing Code
    step = 4;
    console.log("[Test Client] Testing invalid pairing code rejection...");
    sendRequest("req_invalid_pair", "pairing.verify", { code: "000000" });
    return;
  }

  // Step 4: Handle Invalid Pairing Code Response
  if (step === 4 && msg.id === "req_invalid_pair") {
    if (msg.success || msg.error?.code !== "INVALID_PAIRING_CODE") {
      throw new Error(`Expected INVALID_PAIRING_CODE error, got: ${JSON.stringify(msg)}`);
    }
    console.log("  [Step 4 PASS] Invalid code properly rejected with INVALID_PAIRING_CODE.");

    // Step 5: Send Valid Pairing Code
    step = 5;
    console.log(`[Test Client] Sending valid pairing code verification...`);
    sendRequest("req_valid_pair", "pairing.verify", {
      code: PAIRING_CODE,
      name: "Flutter Test Device",
      platform: "ios",
    });
    return;
  }

  // Step 5: Handle Pairing Verification Response & Event
  if (step === 5) {
    if (msg.type === "response" && msg.id === "req_valid_pair") {
      if (!msg.success || !msg.payload?.paired || !msg.payload?.deviceId) {
        throw new Error(`Pairing verification failed: ${JSON.stringify(msg)}`);
      }
      console.log("  [Step 5 PASS] Pairing response success! Assigned DeviceId:", msg.payload.deviceId);
      return;
    }

    if (msg.type === "event" && msg.event === "device.paired") {
      console.log("  [Step 5 PASS] Received device.paired broadcast event:", JSON.stringify(msg.payload));

      // Step 6: Request Agent Status as paired client
      step = 6;
      console.log("[Test Client] Requesting real agent.status as paired client...");
      sendRequest("req_agent_status", "agent.status", {});
      return;
    }
  }

  // Step 6: Handle Agent Status Response
  if (step === 6 && msg.id === "req_agent_status") {
    if (!msg.success || msg.payload?.status !== "online") {
      throw new Error(`Agent status failed: ${JSON.stringify(msg)}`);
    }
    console.log("  [Step 6 PASS] Real agent.status received:", JSON.stringify(msg.payload));

    // Step 7: Request System Info as paired client
    step = 7;
    console.log("[Test Client] Requesting real system.info as paired client...");
    sendRequest("req_system_info", "system.info", {});
    return;
  }

  // Step 7: Handle System Info Response
  if (step === 7 && msg.id === "req_system_info") {
    if (!msg.success || !msg.payload?.hostname || !msg.payload?.os) {
      throw new Error(`System info failed: ${JSON.stringify(msg)}`);
    }
    console.log("  [Step 7 PASS] Real system.info received:", JSON.stringify({
      hostname: msg.payload.hostname,
      os: msg.payload.os,
      architecture: msg.payload.architecture,
      networkInterfaces: msg.payload.network?.length ?? 0,
    }));

    // Step 8: Clean disconnect
    console.log("\n==========================================");
    console.log(" ALL INTEGRATION TEST PHASES PASSED! ");
    console.log("==========================================\n");
    ws.close();
    process.exit(0);
  }
};

ws.onerror = (err) => {
  console.error("[Test Client] WebSocket error:", err);
  process.exit(1);
};

ws.onclose = () => {
  console.log("[Test Client] Connection closed cleanly.");
};

// Timeout safeguard
setTimeout(() => {
  console.error("[Test Client] TIMEOUT: Test did not complete within 10 seconds.");
  process.exit(1);
}, 10000);
