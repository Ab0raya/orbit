/**
 * Orbit Remote Terminal Integration Test Client
 *
 * Verifies end-to-end PTY lifecycle over WebSocket:
 * 1. Connects to ws://127.0.0.1:4371
 * 2. Receives welcome event
 * 3. Sends pairing.verify to authenticate session
 * 4. Creates terminal via terminal.create
 * 5. Receives terminal.created event & response
 * 6. Sends terminal.input with `echo ORBIT_TEST\n`
 * 7. Receives streamed terminal.output containing `ORBIT_TEST`
 * 8. Resizes terminal via terminal.resize
 * 9. Queries terminal.history and asserts `ORBIT_TEST` exists
 * 10. Kills terminal via terminal.kill
 * 11. Receives terminal.exited event
 * 12. Disconnects cleanly
 */

const WS_URL = process.env.ORBIT_WS_URL || "ws://127.0.0.1:4371";
const PAIRING_CODE = process.env.ORBIT_TEST_PAIRING_CODE || "842917";

console.log(`[Terminal Test] Connecting to Orbit Desktop Agent at ${WS_URL}...`);

const ws = new WebSocket(WS_URL);

let step = 0;
let terminalSessionId = null;
let receivedOutput = "";

function sendRequest(id, action, payload = {}) {
  const req = {
    id,
    type: "request",
    action,
    payload,
  };
  console.log(`[Terminal Test] -> Sent request: [${action}] (id: ${id})`);
  ws.send(JSON.stringify(req));
}

ws.onopen = () => {
  console.log("[Terminal Test] Socket connected successfully.");
};

ws.onmessage = (event) => {
  const raw = event.data.toString();
  const msg = JSON.parse(raw);
  console.log(`[Terminal Test] <- Received: type="${msg.type}"`, msg.action ? `action="${msg.action}"` : `event="${msg.event}"`);

  // Step 1: Handle Welcome Event
  if (msg.type === "event" && msg.event === "welcome") {
    console.log("  [Step 1 PASS] Received welcome event:", JSON.stringify(msg.payload));
    // Step 2: Authenticate via pairing.verify
    step = 2;
    console.log(`[Terminal Test] Authenticating mobile session with pairing code...`);
    sendRequest("req_pair", "pairing.verify", {
      code: PAIRING_CODE,
      name: "Flutter Terminal Client",
      platform: "android",
    });
    return;
  }

  // Step 2: Handle Pairing Verification Response
  if (step === 2 && msg.id === "req_pair") {
    if (!msg.success || !msg.payload?.paired) {
      throw new Error(`Pairing verification failed: ${JSON.stringify(msg)}`);
    }
    console.log("  [Step 2 PASS] Paired successfully. DeviceId:", msg.payload.deviceId);

    // Step 3: Create Terminal
    step = 3;
    console.log("[Terminal Test] Creating remote PTY session...");
    sendRequest("req_term_create", "terminal.create", {
      cols: 120,
      rows: 30,
    });
    return;
  }

  // Step 3: Handle terminal.create Response
  if (step === 3 && msg.id === "req_term_create") {
    if (!msg.success || !msg.payload?.sessionId) {
      throw new Error(`Terminal creation failed: ${JSON.stringify(msg)}`);
    }
    terminalSessionId = msg.payload.sessionId;
    console.log("  [Step 3 PASS] Terminal session created:", terminalSessionId, "Shell:", msg.payload.shell);
    return;
  }

  // Step 4: Handle terminal.created Event
  if (msg.type === "event" && msg.event === "terminal.created") {
    if (msg.payload?.sessionId === terminalSessionId) {
      console.log("  [Step 4 PASS] Received terminal.created event for session:", msg.payload.sessionId);

      // Step 5: Send terminal.input with echo command
      step = 5;
      console.log(`[Terminal Test] Sending terminal.input: "echo ORBIT_TEST\\n"...`);
      sendRequest("req_term_input", "terminal.input", {
        sessionId: terminalSessionId,
        data: "echo ORBIT_TEST\n",
      });
      return;
    }
  }

  // Step 5: Handle terminal.input Response
  if (step === 5 && msg.id === "req_term_input") {
    if (!msg.success) {
      throw new Error(`Terminal input failed: ${JSON.stringify(msg)}`);
    }
    console.log("  [Step 5 PASS] Terminal input accepted.");
    step = 6;
    return;
  }

  // Step 6: Listen for streaming terminal.output containing ORBIT_TEST
  if (msg.type === "event" && msg.event === "terminal.output") {
    if (msg.payload?.sessionId === terminalSessionId) {
      receivedOutput += msg.payload.data;
      if (receivedOutput.includes("ORBIT_TEST")) {
        console.log("  [Step 6 PASS] Streamed terminal.output received containing 'ORBIT_TEST'!");

        // Step 7: Resize terminal
        step = 7;
        console.log("[Terminal Test] Resizing terminal to cols=100, rows=35...");
        sendRequest("req_term_resize", "terminal.resize", {
          sessionId: terminalSessionId,
          cols: 100,
          rows: 35,
        });
      }
      return;
    }
  }

  // Step 7: Handle terminal.resize Response
  if (step === 7 && msg.id === "req_term_resize") {
    if (!msg.success) {
      throw new Error(`Terminal resize failed: ${JSON.stringify(msg)}`);
    }
    console.log("  [Step 7 PASS] Terminal resized successfully.");

    // Step 8: Query terminal.history
    step = 8;
    console.log("[Terminal Test] Requesting rolling terminal.history buffer...");
    sendRequest("req_term_hist", "terminal.history", {
      sessionId: terminalSessionId,
    });
    return;
  }

  // Step 8: Handle terminal.history Response
  if (step === 8 && msg.id === "req_term_hist") {
    if (!msg.success || !msg.payload?.data?.includes("ORBIT_TEST")) {
      throw new Error(`History verification failed: ${JSON.stringify(msg)}`);
    }
    console.log("  [Step 8 PASS] Rolling history verified! Length:", msg.payload.data.length, "bytes.");

    // Step 9: Kill terminal session
    step = 9;
    console.log("[Terminal Test] Killing terminal session...");
    sendRequest("req_term_kill", "terminal.kill", {
      sessionId: terminalSessionId,
    });
    return;
  }

  // Step 9: Handle terminal.kill Response
  if (step === 9 && msg.id === "req_term_kill") {
    if (!msg.success) {
      throw new Error(`Terminal kill failed: ${JSON.stringify(msg)}`);
    }
    console.log("  [Step 9 PASS] Kill request accepted.");
    return;
  }

  // Step 10: Handle terminal.exited Event
  if (msg.type === "event" && msg.event === "terminal.exited") {
    if (msg.payload?.sessionId === terminalSessionId) {
      console.log("  [Step 10 PASS] Received terminal.exited event with exitCode:", msg.payload.exitCode);

      console.log("\n==========================================");
      console.log(" ALL REMOTE TERMINAL TEST PHASES PASSED! ");
      console.log("==========================================\n");
      ws.close();
      process.exit(0);
    }
  }
};

ws.onerror = (err) => {
  console.error("[Terminal Test] WebSocket error:", err);
  process.exit(1);
};

ws.onclose = () => {
  console.log("[Terminal Test] Connection closed cleanly.");
};

// Timeout safeguard
setTimeout(() => {
  console.error("[Terminal Test] TIMEOUT: Test did not complete within 12 seconds.");
  process.exit(1);
}, 12000);
