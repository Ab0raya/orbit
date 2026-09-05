export type AiPermissionRisk = "low" | "medium" | "high";
export type AiPermissionState = "pending" | "approved" | "denied" | "expired" | "cancelled";
export type AiPermissionDecision = "allow" | "always" | "deny";

export interface AiPermissionRequest {
  permissionId: string;
  taskId: string;
  deviceId: string;
  sessionId?: string;
  tool: string;
  action: string;
  target: string;
  patterns: string[];
  projectPath: string;
  risk: AiPermissionRisk;
  state: AiPermissionState;
  metadata: Record<string, unknown>;
  createdAt: number;
  timeoutAt: number;
}
