/*
 * A fake scene, standing in for the engine calls that do not exist yet.
 *
 * The shape here is copied from scene_descriptor.mjson at the repo root
 * rather than invented: an entity list, each with a transform (quaternion
 * rotation, xyzw, matching the file) and a handful of optional named
 * component blocks. When the real descriptor gets a loader, this module's
 * seed data goes away and everything below it — the reads, the writes, the
 * subscription — should still work unchanged, because the panels only ever
 * call these functions and never touch the data directly.
 */

export interface Vector3 {
  x: number;
  y: number;
  z: number;
}

export interface Quaternion {
  x: number;
  y: number;
  z: number;
  w: number;
}

export interface Transform {
  position: Vector3;
  rotation: Quaternion;
  scale: Vector3;
}

export interface CameraComponent {
  fovy: number;
  projection: 'PERSPECTIVE' | 'ORTHOGRAPHIC';
  main: boolean;
}

export interface ModelComponent {
  mesh: string;
  material: string;
}

export interface RigidbodyComponent {
  kind: 'STATIC' | 'DYNAMIC';
  density?: number;
  half_extent: Vector3;
}

export interface EntityStub {
  id: string;
  name: string;
  transform: Transform;
  camera?: CameraComponent;
  model?: ModelComponent;
  rigidbody?: RigidbodyComponent;
}

/** Component blocks an entity doesn't have yet, offered by "Add Component". */
export const COMPONENT_TYPES = ['camera', 'model', 'rigidbody'] as const;
export type ComponentType = (typeof COMPONENT_TYPES)[number];

function vec3(x: number, y: number, z: number): Vector3 {
  return { x, y, z };
}

function identityQuat(): Quaternion {
  return { x: 0, y: 0, z: 0, w: 1 };
}

// Same four entities as scene_descriptor.mjson, id = slugified name since the
// real descriptor has no id field of its own.
const entities: EntityStub[] = [
  {
    id: 'main-camera',
    name: 'main camera',
    transform: { position: vec3(0, 10, 20), rotation: identityQuat(), scale: vec3(1, 1, 1) },
    camera: { fovy: 45.0, projection: 'PERSPECTIVE', main: true },
  },
  {
    id: 'ground',
    name: 'ground',
    transform: { position: vec3(0, -0.5, 0), rotation: identityQuat(), scale: vec3(1, 1, 1) },
    model: { mesh: 'models/ground.obj', material: 'materials/dirt.mat' },
    rigidbody: { kind: 'STATIC', half_extent: vec3(25, 0.5, 25) },
  },
  {
    id: 'crate',
    name: 'crate',
    transform: { position: vec3(0, 8, 0), rotation: identityQuat(), scale: vec3(1, 1, 1) },
    model: { mesh: 'models/box.obj', material: 'materials/crate.mat' },
    rigidbody: { kind: 'DYNAMIC', density: 1.0, half_extent: vec3(0.5, 0.5, 0.5) },
  },
  {
    id: 'spawn-point',
    name: 'spawn point',
    transform: { position: vec3(2, 0, -3), rotation: identityQuat(), scale: vec3(1, 1, 1) },
  },
];

let selectedId: string | null = entities[0].id;

// ---------------------------------------------------------------- events ---

/*
 * Every mutation calls this instead of returning a value the caller has to
 * remember to re-render with. Both panels subscribe once at mount and never
 * poll, so a change from either side (select a row, drag a field) shows up
 * in both without them knowing about each other.
 */
type Listener = () => void;
const listeners = new Set<Listener>();

export function subscribe(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function notify(): void {
  for (const listener of listeners) listener();
}

// ----------------------------------------------------------------- reads ---

export function getEntities(): readonly EntityStub[] {
  return entities;
}

export function getEntity(id: string): EntityStub | undefined {
  return entities.find((entity) => entity.id === id);
}

export function getSelectedId(): string | null {
  return selectedId;
}

export function getSelected(): EntityStub | undefined {
  return selectedId ? getEntity(selectedId) : undefined;
}

// ---------------------------------------------------------------- writes ---

export function select(id: string): void {
  if (id === selectedId || !getEntity(id)) return;
  selectedId = id;
  notify();
}

export function rename(id: string, name: string): void {
  const entity = getEntity(id);
  if (!entity || !name.trim()) return;
  entity.name = name.trim();
  notify();
}

export function setVector3(
  id: string,
  field: 'position' | 'scale',
  patch: Partial<Vector3>
): void {
  const entity = getEntity(id);
  if (!entity) return;
  Object.assign(entity.transform[field], patch);
  notify();
}

export function setRotation(id: string, patch: Partial<Quaternion>): void {
  const entity = getEntity(id);
  if (!entity) return;
  Object.assign(entity.transform.rotation, patch);
  notify();
}

export function setCamera(id: string, patch: Partial<CameraComponent>): void {
  const entity = getEntity(id);
  if (!entity?.camera) return;
  Object.assign(entity.camera, patch);
  notify();
}

export function setRigidbody(id: string, patch: Partial<RigidbodyComponent>): void {
  const entity = getEntity(id);
  if (!entity?.rigidbody) return;
  Object.assign(entity.rigidbody, patch);
  notify();
}

/** Adds a stub component block with placeholder values. No-op if already present. */
export function addComponent(id: string, type: ComponentType): void {
  const entity = getEntity(id);
  if (!entity || entity[type]) return;

  if (type === 'camera') {
    entity.camera = { fovy: 60, projection: 'PERSPECTIVE', main: false };
  } else if (type === 'model') {
    entity.model = { mesh: '', material: '' };
  } else if (type === 'rigidbody') {
    entity.rigidbody = { kind: 'STATIC', half_extent: vec3(1, 1, 1) };
  }
  notify();
}

export function removeComponent(id: string, type: ComponentType): void {
  const entity = getEntity(id);
  if (!entity) return;
  delete entity[type];
  notify();
}
