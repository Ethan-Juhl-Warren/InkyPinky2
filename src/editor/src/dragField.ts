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

// TODO: build the actual element (an input box) and return it.
// TODO: make dragging left/right change the value.
// TODO: make clicking (without dragging) let you type a number in.
// TODO: call options.onChange whenever the value changes.
export function createDragField(options: DragFieldOptions): DragField {
  const el = document.createElement('div');
  el.className = 'drag-field';

  return {
    el,
    setValue(_value: number) {
      // TODO: update what's shown in the box.
    },
  };
}
