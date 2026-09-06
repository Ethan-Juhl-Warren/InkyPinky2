// A row of drag fields, one per axis (x/y/z, or x/y/z/w for a quaternion).

import { createDragField } from './dragField';

export interface AxisRowOptions {
  values: Record<string, number>;
  onChange: (axis: string, value: number) => void;
}

const AXIS_COLORS: Record<string, string> = {
  x: '#e05f5f',
  y: '#5fbf5f',
  z: '#5f8fe0',
  w: '#b05fe0',
};

export function createAxisRow(options: AxisRowOptions): HTMLElement {
  const row = document.createElement('div');
  row.className = 'axis-row';

  for (const axis of Object.keys(options.values)) {
    const item = document.createElement('div');
    item.className = 'axis-item';

    const label = document.createElement('span');
    label.className = 'axis-label';
    label.textContent = axis.toUpperCase();
    label.style.color = AXIS_COLORS[axis] ?? 'var(--muted)';
    item.appendChild(label);

    const field = createDragField({
      value: options.values[axis],
      accent: AXIS_COLORS[axis],
      onChange: (value) => options.onChange(axis, value),
    });
    item.appendChild(field.el);

    row.appendChild(item);
  }

  return row;
}
