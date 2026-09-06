// A number box you can drag left/right to change, or click to type into.
// Used for single values like one axis of position/rotation/scale.

export interface DragFieldOptions {
  value: number;
  step?: number;
  accent?: string; // optional color for the little edge stripe (axis color)
  onChange: (value: number) => void;
}

export interface DragField {
  el: HTMLElement;
  setValue: (value: number) => void;
}

const DRAG_PIXELS_PER_STEP = 4; // pixels of mouse movement per one `step` of change

export function createDragField(options: DragFieldOptions): DragField {
  const step = options.step ?? 0.1;
  let value = options.value;
  let dragged = false;

  const el = document.createElement('div');
  el.className = 'drag-field';
  if (options.accent) {
    el.style.setProperty('--drag-field-accent', options.accent);
  }

  const input = document.createElement('input');
  input.type = 'text';
  input.className = 'drag-field-input';
  input.value = formatValue(value);
  input.readOnly = true;
  el.appendChild(input);

  function formatValue(v: number): string {
    return Number.isInteger(v) ? String(v) : v.toFixed(3);
  }

  function commit(next: number): void {
    value = next;
    input.value = formatValue(value);
    options.onChange(value);
  }

  function enterEditMode(): void {
    input.readOnly = false;
    input.value = String(value);
    input.focus();
    input.select();
  }

  function exitEditMode(apply: boolean): void {
    input.readOnly = true;
    if (apply) {
      const parsed = parseFloat(input.value);
      if (!Number.isNaN(parsed)) {
        commit(parsed);
        return;
      }
    }
    input.value = formatValue(value);
  }

  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      exitEditMode(true);
      input.blur();
    } else if (event.key === 'Escape') {
      exitEditMode(false);
      input.blur();
    }
    // Stop movement-key shortcuts (WASD etc.) from firing while typing.
    event.stopPropagation();
  });

  input.addEventListener('blur', () => {
    if (!input.readOnly) exitEditMode(true);
  });

  let dragStartX = 0;
  let dragStartValue = 0;

  input.addEventListener('pointerdown', (event) => {
    if (!input.readOnly) return; // already editing, let normal text interaction happen
    dragged = false;
    dragStartX = event.clientX;
    dragStartValue = value;
    input.setPointerCapture(event.pointerId);
  });

  input.addEventListener('pointermove', (event) => {
    if (!input.readOnly || event.buttons !== 1) return;
    const dx = event.clientX - dragStartX;
    if (!dragged && Math.abs(dx) < 2) return;
    dragged = true;
    el.classList.add('dragging');
    const delta = Math.round(dx / DRAG_PIXELS_PER_STEP) * step;
    commit(dragStartValue + delta);
  });

  input.addEventListener('pointerup', (event) => {
    if (input.hasPointerCapture(event.pointerId)) {
      input.releasePointerCapture(event.pointerId);
    }
    el.classList.remove('dragging');
    if (!dragged) {
      enterEditMode();
    }
    dragged = false;
  });

  return {
    el,
    setValue(next: number) {
      value = next;
      if (input.readOnly) input.value = formatValue(value);
    },
  };
}
