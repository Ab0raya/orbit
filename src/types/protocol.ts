/**
 * Orbit WebSocket Communication Protocol (v1.0)
 *
 * Source of truth for desktop and mobile clients.
 */

export interface ProtocolError {
  code:
    | "MALFORMED_MESSAGE"
    | "UNKNOWN_ACTION"
    | "UNAUTHORIZED"
    | "INVALID_PAIRING_CODE"
    | "RATE_LIMITED"
    | "MESSAGE_TOO_LARGE"
    | "INTERNAL_ERROR"
    | string;
  message: string;
}

export interface OrbitRequest<T = Record<string, unknown>> {
  id: string;
  type: "request";
  action:
    | "ping"
    | "pairing.verify"
    | "system.info"
    | "agent.status"
    | "server.info"
    | string;
  payload?: T;
}

export interface OrbitSuccessResponse<T = Record<string, unknown>> {
  id: string;
  type: "response";
  action: string;
  success: true;
  payload: T;
}

export interface OrbitErrorResponse {
  id: string;
  type: "response";
  action: string;
  success: false;
  error: ProtocolError;
}

export type OrbitResponse<T = Record<string, unknown>> =
  | OrbitSuccessResponse<T>
  | OrbitErrorResponse;

export interface OrbitEvent<T = Record<string, unknown>> {
  type: "event";
  event:
    | "welcome"
    | "device.paired"
    | "device.connected"
    | "device.disconnected"
    | string;
  payload: T;
}

/**
 * Root discriminated union for all Orbit WebSocket traffic.
 */
export type OrbitMessage =
  | OrbitRequest
  | OrbitResponse
  | OrbitEvent;

/* Specific Action Payloads */

export interface PingResponsePayload {
  timestamp: number;
}

export interface PairingVerifyPayload {
  code: string;
  name?: string;
  deviceName?: string;
  platform?: "ios" | "android" | "web" | string;
}

export interface PairingVerifyResponsePayload {
  paired: boolean;
  deviceId: string;
}

export interface WelcomeEventPayload {
  server: string;
  version: string;
  protocol: string;
}

export interface DevicePairedEventPayload {
  deviceId: string;
  name: string;
  platform: string;
  pairedAt: number;
}

/* Terminal Protocol Payloads */

export type TerminalStatus = "starting" | "running" | "exited" | "killed" | "failed";

export interface TerminalSessionSummary {
  sessionId: string;
  status: TerminalStatus;
  cwd: string;
  shell: string;
  rows: number;
  cols: number;
  createdAt: number;
  lastActivityAt: number;
  exitCode?: number;
  ownerDeviceId: string;
}

export interface TerminalCreatePayload {
  cwd?: string;
  cols?: number;
  rows?: number;
}

export interface TerminalCreateResponsePayload {
  sessionId: string;
  cwd: string;
  shell: string;
  rows: number;
  cols: number;
}

export interface TerminalInputPayload {
  sessionId: string;
  data: string;
}

export interface TerminalResizePayload {
  sessionId: string;
  cols: number;
  rows: number;
}

export interface TerminalKillPayload {
  sessionId: string;
}

export interface TerminalHistoryPayload {
  sessionId: string;
}

export interface TerminalHistoryResponsePayload {
  sessionId: string;
  data: string;
}

export interface TerminalListResponsePayload {
  sessions: TerminalSessionSummary[];
}

export interface TerminalCreatedEventPayload {
  sessionId: string;
}

export interface TerminalOutputEventPayload {
  sessionId: string;
  data: string;
}

export interface TerminalExitedEventPayload {
  sessionId: string;
  exitCode?: number;
}

export interface TerminalErrorEventPayload {
  sessionId: string;
  error: string;
}

