// A row of drag fields, one per axis (x/y/z, or x/y/z/w for a quaternion).

export interface AxisRowOptions {
  values: Record<string, number>;
  onChange: (axis: string, value: number) => void;
}

// TODO: make one labeled drag field per axis in values.
// TODO: color each axis label (x = red, y = green, z = blue, w = purple).
// TODO: put them all in one row and return that row.
export function createAxisRow(options: AxisRowOptions): HTMLElement {
  const row = document.createElement('div');
  row.className = 'axis-row';
  return row;
}
