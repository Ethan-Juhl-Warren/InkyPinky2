// The right panel: shows and edits the selected entity's values.

export interface InspectorOptions {
  container: HTMLElement;
}

// TODO: get the selected entity from sceneStub.getSelected().
// TODO: show its name at the top (editable text field).
// TODO: show a "Transform" section with position / rotation / scale rows,
//       using createAxisRow for each (rotation is a quaternion, so x/y/z/w).
// TODO: make the Transform section collapsible (click header to expand/collapse).
// TODO: inside Transform, add a smaller collapsible area for extra/inherited
//       info (e.g. world position) - this is the "dropdown after Transform"
//       mentioned in the request.
// TODO: show a section per optional component the entity has (camera, model,
//       rigidbody), each with its own basic fields.
// TODO: add an "Add Component" button/dropdown listing component types the
//       entity doesn't have yet, calling sceneStub.addComponent(id, type).
// TODO: re-draw whenever sceneStub.subscribe() fires or the selection changes.
export function mountInspector(options: InspectorOptions): void {
  // stub
}
