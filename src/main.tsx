import React, { Component, ErrorInfo, ReactNode } from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./index.css";

// Telemetry helper for webview debugging
const reportStartup = (stage: string, detail?: any) => {
  console.log(`[Orbit UI] ${stage}`, detail || "");
  try {
    fetch("http://127.0.0.1:9999/stage", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ stage, detail: detail ? String(detail) : undefined, time: Date.now() }),
    }).catch(() => {});
  } catch {}
};

reportStartup("React boot");

window.addEventListener("error", (event) => {
  console.error("[Orbit UI] Uncaught global error:", event.error || event.message);
  reportStartup("Global error", event.error?.stack || event.message);
});

window.addEventListener("unhandledrejection", (event) => {
  console.error("[Orbit UI] Unhandled promise rejection:", event.reason);
  reportStartup("Unhandled rejection", event.reason?.stack || event.reason);
});

interface ErrorBoundaryProps {
  children: ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null, errorInfo: null };
  }

  static getDerivedStateFromError(error: Error): Partial<ErrorBoundaryState> {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error("[Orbit UI] Error caught by ErrorBoundary:", error, errorInfo);
    reportStartup("ErrorBoundary caught", {
      message: error.message,
      stack: error.stack,
      componentStack: errorInfo.componentStack,
    });
    this.setState({ errorInfo });
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null, errorInfo: null });
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      return (
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            minHeight: "100vh",
            width: "100vw",
            backgroundColor: "#050505",
            color: "#FFFFFF",
            fontFamily: "'DM Sans', -apple-system, BlinkMacSystemFont, sans-serif",
            padding: "24px",
            boxSizing: "border-box",
            textAlign: "center",
          }}
        >
          <div
            style={{
              maxWidth: "520px",
              width: "100%",
              backgroundColor: "#0D0D0D",
              border: "1px solid rgba(255, 255, 255, 0.12)",
              borderRadius: "16px",
              padding: "36px 32px",
              boxShadow: "0 20px 40px rgba(0,0,0,0.8)",
            }}
          >
            <div
              style={{
                display: "inline-flex",
                alignItems: "center",
                justifyContent: "center",
                width: "48px",
                height: "48px",
                borderRadius: "12px",
                backgroundColor: "rgba(239, 68, 68, 0.12)",
                color: "#EF4444",
                marginBottom: "20px",
                fontSize: "24px",
              }}
            >
              ⚠
            </div>
            <div
              style={{
                fontSize: "12px",
                letterSpacing: "0.15em",
                textTransform: "uppercase",
                color: "#A1A1AA",
                fontWeight: 600,
                marginBottom: "6px",
              }}
            >
              ORBIT
            </div>
            <h1
              style={{
                fontSize: "22px",
                fontWeight: 600,
                color: "#FFFFFF",
                margin: "0 0 12px 0",
              }}
            >
              Application Error
            </h1>
            <p
              style={{
                fontSize: "14px",
                color: "#A1A1AA",
                lineHeight: "1.6",
                margin: "0 0 24px 0",
              }}
            >
              Something went wrong while loading the desktop interface.
            </p>

            {this.state.error && (
              <div
                style={{
                  backgroundColor: "#050505",
                  border: "1px solid rgba(255, 255, 255, 0.08)",
                  borderRadius: "8px",
                  padding: "12px",
                  marginBottom: "24px",
                  textAlign: "left",
                  overflowX: "auto",
                  maxHeight: "160px",
                }}
              >
                <code
                  style={{
                    fontFamily: "'JetBrains Mono', monospace",
                    fontSize: "12px",
                    color: "#EF4444",
                    display: "block",
                    whiteSpace: "pre-wrap",
                    wordBreak: "break-word",
                  }}
                >
                  {this.state.error.toString()}
                </code>
              </div>
            )}

            <button
              onClick={this.handleRetry}
              style={{
                padding: "10px 24px",
                backgroundColor: "#FFFFFF",
                color: "#000000",
                border: "none",
                borderRadius: "8px",
                fontSize: "14px",
                fontWeight: 600,
                cursor: "pointer",
                transition: "opacity 0.15s ease",
              }}
              onMouseEnter={(e) => ((e.currentTarget as HTMLElement).style.opacity = "0.9")}
              onMouseLeave={(e) => ((e.currentTarget as HTMLElement).style.opacity = "1")}
            >
              Retry
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

reportStartup("Providers initialized");
reportStartup("Router initialized");

const rootElement = document.getElementById("root");
if (rootElement) {
  ReactDOM.createRoot(rootElement).render(
    <React.StrictMode>
      <ErrorBoundary>
        <App />
      </ErrorBoundary>
    </React.StrictMode>
  );
  reportStartup("App mounted");
} else {
  reportStartup("Fatal: #root element missing");
}

