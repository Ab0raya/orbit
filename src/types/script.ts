export interface Script {
  id: string;
  name: string;
  description?: string | null;
  content: string;
  workingDirectory?: string | null;
  projectPath?: string | null;
  createdAt: number;
  updatedAt: number;
}

export interface ScriptInput {
  id?: string | null;
  name: string;
  description?: string | null;
  content: string;
  workingDirectory?: string | null;
  projectPath?: string | null;
}
