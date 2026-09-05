import React, { useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import {
  FileText,
  Eye,
  Code,
  Copy,
  Check,
  Search,
  Sparkles,
  Edit3,
  ExternalLink,
} from "lucide-react";

export interface MarkdownViewerProps {
  fileName: string;
  filePath: string;
  content: string;
  onContentChange?: (newContent: string) => void;
  onAskAi?: (filePath: string, content: string) => void;
  onClose?: () => void;
}

export const MarkdownViewer: React.FC<MarkdownViewerProps> = ({
  fileName,
  filePath,
  content,
  onContentChange,
  onAskAi,
}) => {
  const [viewMode, setViewMode] = useState<"markdown" | "source">("markdown");
  const [copied, setCopied] = useState(false);
  const [editableContent, setEditableContent] = useState(content);
  const [isEditing, setIsEditing] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [showSearch, setShowSearch] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(editableContent);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (e) {
      console.error("Failed to copy markdown text:", e);
    }
  };

  const handleAskAi = () => {
    if (onAskAi) {
      onAskAi(filePath, editableContent);
    } else {
      // Copy snippet with context note
      navigator.clipboard.writeText(
        `File: ${filePath}\n\n${editableContent.slice(0, 4000)}`
      );
      alert(`Attached ${fileName} context to clipboard for Orbit AI.`);
    }
  };

  const handleEditToggle = () => {
    if (viewMode === "markdown") {
      setViewMode("source");
      setIsEditing(true);
    } else {
      setIsEditing(!isEditing);
    }
  };

  return (
    <div className="markdown-viewer-container">
      {/* Top Header Bar */}
      <div className="markdown-header">
        <div className="markdown-header-left">
          <div className="markdown-file-icon">
            <FileText size={16} className="text-accent" />
          </div>
          <div className="markdown-title-meta">
            <div className="markdown-title-row">
              <span className="markdown-filename">{fileName}</span>
              <span className="markdown-badge">Markdown</span>
            </div>
            <span className="markdown-filepath" title={filePath}>
              {filePath}
            </span>
          </div>
        </div>

        {/* Actions */}
        <div className="markdown-header-actions">
          {/* Segmented Mode Toggle: [ Markdown ] [ Source ] */}
          <div className="segmented-toggle">
            <button
              className={`toggle-btn ${viewMode === "markdown" ? "active" : ""}`}
              onClick={() => {
                setViewMode("markdown");
                setIsEditing(false);
              }}
              title="Rendered Markdown Preview"
            >
              <Eye size={13} />
              <span>Markdown</span>
            </button>
            <button
              className={`toggle-btn ${viewMode === "source" ? "active" : ""}`}
              onClick={() => setViewMode("source")}
              title="Raw Markdown Source"
            >
              <Code size={13} />
              <span>Source</span>
            </button>
          </div>

          <button
            className={`action-icon-btn ${isEditing ? "btn-active" : ""}`}
            onClick={handleEditToggle}
            title={isEditing ? "Viewing Source" : "Edit Source"}
          >
            <Edit3 size={14} />
            <span className="action-text">Edit</span>
          </button>

          <button
            className="action-icon-btn btn-ai"
            onClick={handleAskAi}
            title="Send file context to Orbit AI"
          >
            <Sparkles size={14} />
            <span className="action-text">Ask Orbit AI</span>
          </button>

          <button
            className={`action-icon-btn ${showSearch ? "btn-active" : ""}`}
            onClick={() => setShowSearch(!showSearch)}
            title="Search in file"
          >
            <Search size={14} />
            <span className="action-text">Search</span>
          </button>

          <button
            className="action-icon-btn"
            onClick={handleCopy}
            title="Copy Markdown text"
          >
            {copied ? <Check size={14} className="text-success" /> : <Copy size={14} />}
            <span className="action-text">{copied ? "Copied" : "Copy"}</span>
          </button>
        </div>
      </div>

      {/* Optional Search Bar */}
      {showSearch && (
        <div className="markdown-search-bar">
          <Search size={14} className="search-icon" />
          <input
            type="text"
            placeholder="Find in document..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            autoFocus
          />
          {searchQuery && (
            <button
              className="clear-search-btn"
              onClick={() => setSearchQuery("")}
            >
              ✕
            </button>
          )}
        </div>
      )}

      {/* Main Content Area */}
      <div className="markdown-body-wrapper">
        {viewMode === "markdown" ? (
          <div className="markdown-rendered-content">
            <ReactMarkdown
              remarkPlugins={[remarkGfm]}
              components={{
                code({ inline, className, children, ...props }: any) {
                  const match = /language-(\w+)/.exec(className || "");
                  const lang = match ? match[1] : "";
                  const codeText = String(children).replace(/\n$/, "");

                  if (!inline && lang) {
                    return (
                      <div className="markdown-code-block">
                        <div className="code-block-header">
                          <span className="code-lang-label">{lang}</span>
                          <button
                            className="code-copy-btn"
                            onClick={() => {
                              navigator.clipboard.writeText(codeText);
                            }}
                            title="Copy code block"
                          >
                            <Copy size={12} />
                            <span>Copy</span>
                          </button>
                        </div>
                        <pre className="code-block-pre">
                          <code className={className} {...props}>
                            {codeText}
                          </code>
                        </pre>
                      </div>
                    );
                  }

                  if (!inline) {
                    return (
                      <div className="markdown-code-block">
                        <div className="code-block-header">
                          <span className="code-lang-label">code</span>
                          <button
                            className="code-copy-btn"
                            onClick={() => {
                              navigator.clipboard.writeText(codeText);
                            }}
                            title="Copy code block"
                          >
                            <Copy size={12} />
                            <span>Copy</span>
                          </button>
                        </div>
                        <pre className="code-block-pre">
                          <code {...props}>{codeText}</code>
                        </pre>
                      </div>
                    );
                  }

                  return (
                    <code className="markdown-inline-code" {...props}>
                      {children}
                    </code>
                  );
                },
                a({ href, children, ...props }) {
                  const safeHref =
                    href && !href.toLowerCase().startsWith("javascript:")
                      ? href
                      : "#";
                  return (
                    <a
                      href={safeHref}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="markdown-link"
                      {...props}
                    >
                      {children}
                      <ExternalLink size={10} className="link-icon" />
                    </a>
                  );
                },
                table({ children }) {
                  return (
                    <div className="markdown-table-wrapper">
                      <table className="markdown-table">{children}</table>
                    </div>
                  );
                },
              }}
            >
              {editableContent}
            </ReactMarkdown>
          </div>
        ) : (
          <div className="markdown-source-container">
            <textarea
              className="markdown-source-textarea"
              value={editableContent}
              onChange={(e) => {
                setEditableContent(e.target.value);
                if (onContentChange) {
                  onContentChange(e.target.value);
                }
              }}
              spellCheck={false}
              placeholder="Markdown source..."
            />
          </div>
        )}
      </div>
    </div>
  );
};
