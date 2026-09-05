export interface FileRoot {
  name: string;
  path: string;
}

export interface FileEntry {
  name: string;
  path: string;
  kind: "file" | "directory";
  size: number;
  modifiedAt?: number;
  hidden: boolean;
}

export interface FileListResult {
  path: string;
  entries: FileEntry[];
}

export interface FileReadResult {
  path: string;
  content: string;
  encoding: string;
  size: number;
}

export interface SearchFileResult {
  path: string;
  name: string;
  relativePath: string;
  isDirectory: boolean;
  lineNumber?: number;
  lineContent?: string;
}

export interface FileSearchResult {
  root: string;
  query: string;
  mode: "name" | "content";
  totalMatches: number;
  truncated: boolean;
  results: SearchFileResult[];
}

export type FileCategory = "markdown" | "code" | "text" | "image" | "binary";

export function getFileCategory(fileNameOrPath: string): FileCategory {
  const ext = fileNameOrPath.split(".").pop()?.toLowerCase() || "";
  if (["md", "markdown", "mdx"].includes(ext)) {
    return "markdown";
  }
  if (
    [
      "ts", "tsx", "js", "jsx", "rs", "py", "dart", "go", "java", "kt",
      "c", "cpp", "h", "hpp", "sh", "bash", "html", "css", "json", "toml",
      "yaml", "yml", "xml", "sql"
    ].includes(ext)
  ) {
    return "code";
  }
  if (["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "ico"].includes(ext)) {
    return "image";
  }
  if (["txt", "log", "env", "ini", "conf"].includes(ext)) {
    return "text";
  }
  return "binary";
}
