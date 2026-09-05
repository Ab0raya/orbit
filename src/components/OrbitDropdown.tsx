import React, { useEffect, useId, useRef, useState } from "react";
import { Check, ChevronDown } from "lucide-react";

export interface OrbitDropdownOption {
  value: string;
  label: string;
  /** Small secondary text shown under/next to the label. */
  sub?: string;
  /** Disabled rows are visible but not selectable (e.g. status hints). */
  disabled?: boolean;
}

interface OrbitDropdownProps {
  value: string;
  options: OrbitDropdownOption[];
  onChange: (value: string) => void;
  /** Shown when value is empty or matches no option and no options exist. */
  placeholder?: string;
  /** Honest busy state: keeps the control readable, blocks interaction. */
  loading?: boolean;
  loadingText?: string;
  disabled?: boolean;
  ariaLabel?: string;
  /** Test hook. */
  dataTestId?: string;
}

/**
 * Orbit-styled dropdown: dark trigger + floating panel, full keyboard
 * support (Enter/Esc/Arrows), outside-click to close. Purely presentational:
 * options and state always come from the caller (no mock data inside).
 */
export const OrbitDropdown: React.FC<OrbitDropdownProps> = ({
  value,
  options,
  onChange,
  placeholder = "Select...",
  loading = false,
  loadingText = "Loading...",
  disabled = false,
  ariaLabel,
  dataTestId,
}) => {
  const [open, setOpen] = useState(false);
  const [highlight, setHighlight] = useState<number>(-1);
  const rootRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const listId = useId();

  const interactive = !disabled && !loading;
  const selected = options.find((o) => o.value === value) || null;

  const close = () => {
    setOpen(false);
    setHighlight(-1);
  };

  // Outside click / pointer close.
  useEffect(() => {
    if (!open) return;
    const onPointerDown = (e: MouseEvent | TouchEvent) => {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) {
        close();
      }
    };
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("touchstart", onPointerDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("touchstart", onPointerDown);
    };
  }, [open ]);

  // Keep the highlighted option visible while navigating.
  useEffect(() => {
    if (!open || highlight < 0) return;
    const el = listRef.current?.querySelector<HTMLElement>(
      `[data-orbit-option-index="${highlight}"]`
    );
    el?.scrollIntoView({ block: "nearest" });
  }, [open, highlight]);

  const selectableIndexes = (opts: OrbitDropdownOption[]): number[] =>
    opts.map((o, i) => (o.disabled ? -1 : i)).filter((i) => i >= 0);

  const openMenu = () => {
    if (!interactive) return;
    const idx = options.findIndex((o) => o.value === value && !o.disabled);
    setHighlight(idx);
    setOpen(true);
  };

  const commit = (index: number) => {
    const opt = options[index];
    if (!opt || opt.disabled) return;
    if (opt.value !== value) onChange(opt.value);
    close();
  };

  const moveHighlight = (dir: 1 | -1) => {
    const sel = selectableIndexes(options);
    if (sel.length === 0) return;
    const pos = sel.indexOf(highlight);
    const next = pos < 0 ? (dir > 0 ? sel[0] : sel[sel.length - 1]) : sel[(pos + dir + sel.length) % sel.length];
    setHighlight(next);
  };

  const onTriggerKeyDown = (e: React.KeyboardEvent) => {
    if (!interactive) return;
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      if (!open) {
        openMenu();
      } else {
        const sel = selectableIndexes(options);
        if (sel.length > 0) commit(highlight >= 0 ? highlight : sel[0]);
      }
    } else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (!open) {
        openMenu();
      } else {
        moveHighlight(e.key === "ArrowDown" ? 1 : -1);
      }
    } else if (e.key === "Escape") {
      if (open) {
        e.preventDefault();
        close();
      }
    }
  };

  const onListKeyDown = (e: React.KeyboardEvent) => {
    const sel = selectableIndexes(options);
    if (e.key === "Escape") {
      e.preventDefault();
      close();
      return;
    }
    if (sel.length === 0) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      moveHighlight(e.key === "ArrowDown" ? 1 : -1);
    } else if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      if (highlight >= 0) commit(highlight);
    } else if (e.key === "Tab") {
      close();
    }
  };

  return (
    <div ref={rootRef} className="orbit-dropdown" data-testid={dataTestId}>
      <button
        type="button"
        className={`orbit-dropdown-trigger${open ? " orbit-dropdown-open" : ""}${loading ? " orbit-dropdown-loading" : ""}`}
        onClick={() => (open ? close() : openMenu())}
        onKeyDown={onTriggerKeyDown}
        disabled={!interactive}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        aria-label={ariaLabel}
      >
        <span className="orbit-dropdown-value font-mono">
          {loading ? loadingText : selected ? selected.label : placeholder}
        </span>
        {loading ? (
          <span className="orbit-dropdown-spinner" aria-hidden="true" />
        ) : (
          <ChevronDown size={14} className="orbit-dropdown-chevron" aria-hidden="true" />
        )}
      </button>

      {open && (
        <div
          id={listId}
          ref={listRef}
          role="listbox"
          tabIndex={-1}
          aria-label={ariaLabel}
          className="orbit-dropdown-panel"
          onKeyDown={onListKeyDown}
        >
          {options.length === 0 && (
            <div className="orbit-dropdown-empty font-mono">No options available</div>
          )}
          {options.map((opt, i) => {
            const isSelected = opt.value === value;
            const isActive = i === highlight;
            return (
              <div
                key={`${opt.value}-${i}`}
                role="option"
                aria-selected={isSelected}
                aria-disabled={opt.disabled || undefined}
                data-orbit-option-index={i}
                tabIndex={-1}
                className={[
                  "orbit-dropdown-option",
                  isSelected ? "orbit-dropdown-selected" : "",
                  isActive ? "orbit-dropdown-active" : "",
                  opt.disabled ? "orbit-dropdown-disabled" : "",
                ].join(" ")}
                onMouseEnter={() => {
                  if (!opt.disabled) setHighlight(i);
                }}
                onClick={() => commit(i)}
              >
                <span className="orbit-dropdown-option-main">
                  <span className="orbit-dropdown-option-label font-mono">{opt.label}</span>
                  {opt.sub && (
                    <span className="orbit-dropdown-option-sub font-mono">{opt.sub}</span>
                  )}
                </span>
                {isSelected && (
                  <Check size={13} className="orbit-dropdown-check" aria-hidden="true" />
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
