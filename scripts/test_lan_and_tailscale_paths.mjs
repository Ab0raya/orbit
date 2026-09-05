/**
 * Test LAN and Tailscale Connection Paths
 * 
 * Verifies:
 * 1. Desktop server binds and reports Tailscale metadata.
 * 2. LAN connection path connects, pairs, and exchanges messages.
 * 3. Tailscale connection path connects, pairs/resumes, and exchanges messages.
 * 4. Fallback path: when LAN is unreachable, fallback to Tailscale succeeds.
 */

import { spawn } from 'child_process';
import http from 'http';

const DAEMON_BIN = './src-tauri/target/debug/orbit_daemon';
const PORT = 4371;
const MOCK_TS_IP = '127.0.0.1'; // Use loopback as the accessible Tailscale endpoint for live socket test
const UNREACHABLE_LAN_IP = '192.0.2.1'; // RFC 5737 TEST-NET-1 (guaranteed unreachable)

console.log('[Test] Starting Orbit Daemon with Tailscale mock state...');

const daemonEnv = {
  ...process.env,
  ORBIT_TAILSCALE_MOCK_STATE: 'connected',
  ORBIT_TAILSCALE_MOCK_IP: MOCK_TS_IP,
  ORBIT_TAILSCALE_MOCK_DEVICE: 'orbit-dev-box.tailnet.ts.net',
};

const daemon = spawn(DAEMON_BIN, [], {
  env: daemonEnv,
  stdio: ['pipe', 'pipe', 'pipe'],
});

let pairingCode = null;
let pairingUri = null;

daemon.stdout.on('data', (chunk) => {
  const text = chunk.toString();
  process.stdout.write(`[Daemon] ${text}`);
  const codeMatch = text.match(/Pairing Code:\s*(\d{6})/);
  if (codeMatch) {
    pairingCode = codeMatch[1];
  }
  const uriMatch = text.match(/Pairing URI:\s*(\S+)/);
  if (uriMatch) {
    pairingUri = uriMatch[1];
  }
});

daemon.stderr.on('data', (chunk) => {
  process.stderr.write(`[Daemon ERR] ${chunk}`);
});

// Helper to wait
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Helper to create a WebSocket connection and send/receive a request
async function testWebSocketPath(name, host, port, codeToVerify, shouldExpectFail = false) {
  return new Promise((resolve, reject) => {
    console.log(`\n--- Testing ${name} on ws://${host}:${port} ---`);
    const wsUrl = `ws://${host}:${port}`;
    let socket;
    let timer;

    timer = setTimeout(() => {
      if (shouldExpectFail) {
        console.log(`  [Expected Timeout/Failure] Path ${name} failed as expected.`);
        if (socket) socket.close();
        resolve(false);
      } else {
        if (socket) socket.close();
        reject(new Error(`Timeout connecting to ${wsUrl}`));
      }
    }, shouldExpectFail ? 1500 : 5000);

    try {
      socket = new WebSocket(wsUrl);
    } catch (e) {
      if (shouldExpectFail) {
        clearTimeout(timer);
        console.log(`  [Expected Failure] Immediate connect error: ${e.message}`);
        return resolve(false);
      }
      clearTimeout(timer);
      return reject(e);
    }

    socket.onerror = (err) => {
      if (shouldExpectFail) {
        clearTimeout(timer);
        console.log(`  [Expected Error] Connection to ${wsUrl} failed as expected.`);
        return resolve(false);
      }
      clearTimeout(timer);
      reject(err);
    };

    let sessionToken = null;
    let deviceId = null;

    socket.onopen = () => {
      if (shouldExpectFail) {
        clearTimeout(timer);
        return reject(new Error(`Expected ${name} to fail, but it connected!`));
      }
      console.log(`  [Connected] Socket opened for ${name}`);
    };

    socket.onmessage = (event) => {
      const msg = JSON.parse(event.data.toString());
      if (msg.type === 'event' && msg.event === 'welcome') {
        console.log(`  [Welcome] Received server welcome banner`);
        // Verify pairing
        socket.send(JSON.stringify({
          id: `verify_${name}`,
          type: 'request',
          action: 'pairing.verify',
          payload: {
            code: codeToVerify,
            name: `Test Client (${name})`,
            platform: 'test',
          },
        }));
      } else if (msg.id === `verify_${name}`) {
        if (!msg.success) {
          clearTimeout(timer);
          return reject(new Error(`Pairing verify failed: ${JSON.stringify(msg)}`));
        }
        deviceId = msg.payload.deviceId;
        sessionToken = msg.payload.sessionToken;
        console.log(`  [Paired] Device ID: ${deviceId}`);

        // Query system.info to inspect Tailscale info payload
        socket.send(JSON.stringify({
          id: `sysinfo_${name}`,
          type: 'request',
          action: 'system.info',
          payload: {},
        }));
      } else if (msg.id === `sysinfo_${name}`) {
        if (!msg.success) {
          clearTimeout(timer);
          return reject(new Error(`system.info failed: ${JSON.stringify(msg)}`));
        }
        const ts = msg.payload.tailscale;
        console.log(`  [Tailscale Info] Installed: ${ts?.installed}, State: ${ts?.state}, IP: ${ts?.ip}`);
        if (!ts || ts.state !== 'connected' || ts.ip !== MOCK_TS_IP) {
          clearTimeout(timer);
          return reject(new Error(`Invalid Tailscale metadata: ${JSON.stringify(ts)}`));
        }

        clearTimeout(timer);
        socket.close();
        console.log(`  [Success] ${name} verified successfully!`);
        resolve(true);
      }
    };
  });
}

// Emulate ConnectionManager fallback
async function testConnectionManagerFallback(lanHost, tsHost, port, code) {
  console.log(`\n=== Testing Client Connection Manager Dual-Path Fallback ===`);
  console.log(`  Attempting primary LAN path: ${lanHost}:${port}...`);
  let connected = false;
  try {
    connected = await testWebSocketPath('Unreachable LAN', lanHost, port, code, true);
  } catch (e) {
    connected = false;
  }

  if (!connected) {
    console.log(`  Primary LAN unreachable. Initiating automatic fallback to Tailscale path: ${tsHost}:${port}...`);
    const tsSuccess = await testWebSocketPath('Tailscale Fallback', tsHost, port, code, false);
    if (!tsSuccess) {
      throw new Error('Fallback to Tailscale failed!');
    }
    console.log('  [Fallback PASS] Successfully established session over Tailscale path!');
  }
}

async function run() {
  // Wait for daemon to print pairing code
  let attempts = 0;
  while (!pairingCode && attempts < 30) {
    await sleep(200);
    attempts++;
  }

  if (!pairingCode) {
    daemon.kill();
    throw new Error('Daemon did not start or provide pairing code.');
  }

  console.log(`\nDaemon ready! Pairing Code: ${pairingCode}`);
  console.log(`Daemon Pairing URI: ${pairingUri}`);

  // 1. Verify Pairing URI has ts_host
  if (!pairingUri.includes(`ts_host=${MOCK_TS_IP}`)) {
    throw new Error(`Pairing URI does not contain expected ts_host=${MOCK_TS_IP}: ${pairingUri}`);
  }
  console.log('[QR/URI Verification PASS] QR payload includes &ts_host parameter automatically.');

  // 2. Test LAN Path (ws://127.0.0.1:4371)
  await testWebSocketPath('LAN Path', '127.0.0.1', PORT, pairingCode);

  // 3. Test Direct Tailscale Path
  await testWebSocketPath('Direct Tailscale Path', MOCK_TS_IP, PORT, pairingCode);

  // 4. Test Dual-Path Automatic Fallback (LAN down -> Tailscale up)
  await testConnectionManagerFallback(UNREACHABLE_LAN_IP, MOCK_TS_IP, PORT, pairingCode);

  console.log('\n======================================================');
  console.log(' ALL LAN & TAILSCALE CONNECTION PATH TESTS SUCCEEDED!');
  console.log('======================================================\n');

  daemon.kill('SIGTERM');
  process.exit(0);
}

run().catch((err) => {
  console.error('\n[FATAL TEST FAILURE]', err);
  daemon.kill('SIGTERM');
  process.exit(1);
});
