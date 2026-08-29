// The right panel: shows and edits the selected entity's values.

import {
	getSelected,
	rename,
	setVector3,
	setRotation,
	setCamera,
	setRigidbody,
	addComponent,
	subscribe,
	COMPONENT_TYPES,
	type ComponentType,
} from './sceneStub';
import { createAxisRow } from './vector3Field';

export interface InspectorOptions {
	container: HTMLElement;
}

function createSection(title: string): { section: HTMLElement; body: HTMLElement } {
	const section = document.createElement('div');
	section.className = 'section';

	const header = document.createElement('button');
	header.type = 'button';
	header.className = 'section-header';
	header.textContent = title;

	const body = document.createElement('div');
	body.className = 'section-body';

	header.addEventListener('click', () => {
		body.hidden = !body.hidden;
	});

	section.appendChild(header);
	section.appendChild(body);
	return { section, body };
}

function labeledField(text: string, field: HTMLElement): HTMLElement {
	const row = document.createElement('label');
	row.className = 'field-row';

	const labelEl = document.createElement('span');
	labelEl.textContent = text;

	row.appendChild(labelEl);
	row.appendChild(field);
	return row;
}

export function mountInspector(options: InspectorOptions): void {
	function render(): void {
		options.container.innerHTML = '';

		const selected = getSelected();
		if (!selected) return;

		// ---- name -----------------------------------------------------------
		const selectedName = document.createElement('input');
		selectedName.type = 'text';
		selectedName.value = selected.name;
		selectedName.addEventListener('input', () => {
			rename(selected.id, selectedName.value);
		});
		options.container.appendChild(selectedName);

		// ---- transform --------------------------------------------------------
		const { section: transformSection, body: transformBody } = createSection('Transform');

		transformBody.appendChild(
			createAxisRow({
				values: { ...selected.transform.position },
				onChange: (axis, value) => setVector3(selected.id, 'position', { [axis]: value }),
			})
		);
		transformBody.appendChild(
			createAxisRow({
				values: { ...selected.transform.rotation },
				onChange: (axis, value) => setRotation(selected.id, { [axis]: value }),
			})
		);
		transformBody.appendChild(
			createAxisRow({
				values: { ...selected.transform.scale },
				onChange: (axis, value) => setVector3(selected.id, 'scale', { [axis]: value }),
			})
		);

		// Nested collapsible for extra/inherited info. The stub has no parent
		// hierarchy yet, so "world" position is just local position for now -
		// shown read-only since it isn't an independent source of truth.
		const { section: worldSection, body: worldBody } = createSection('World');
		worldBody.className += ' section-body-nested';
		worldBody.appendChild(
			createAxisRow({
				values: { ...selected.transform.position },
				onChange: () => {},
			})
		);
		transformBody.appendChild(worldSection);

		options.container.appendChild(transformSection);

		// ---- optional components ----------------------------------------------
		if (selected.camera) {
			const camera = selected.camera;
			const { section, body } = createSection('Camera');

			const fovyField = document.createElement('input');
			fovyField.type = 'number';
			fovyField.value = String(camera.fovy);
			fovyField.addEventListener('input', () => {
				const fovy = parseFloat(fovyField.value);
				if (!Number.isNaN(fovy)) setCamera(selected.id, { fovy });
			});
			body.appendChild(labeledField('FOV Y', fovyField));

			const projectionField = document.createElement('select');
			for (const value of ['PERSPECTIVE', 'ORTHOGRAPHIC'] as const) {
				const optionEl = document.createElement('option');
				optionEl.value = value;
				optionEl.textContent = value;
				projectionField.appendChild(optionEl);
			}
			projectionField.value = camera.projection;
			projectionField.addEventListener('change', () => {
				setCamera(selected.id, {
					projection: projectionField.value as 'PERSPECTIVE' | 'ORTHOGRAPHIC',
				});
			});
			body.appendChild(labeledField('Projection', projectionField));

			const mainField = document.createElement('input');
			mainField.type = 'checkbox';
			mainField.checked = camera.main;
			mainField.addEventListener('change', () => {
				setCamera(selected.id, { main: mainField.checked });
			});
			body.appendChild(labeledField('Main', mainField));

			options.container.appendChild(section);
		}

		if (selected.model) {
			const model = selected.model;
			const { section, body } = createSection('Model');

			// sceneStub exposes no setter for model fields yet, so these are
			// display-only until one exists.
			const meshField = document.createElement('input');
			meshField.type = 'text';
			meshField.value = model.mesh;
			meshField.disabled = true;
			body.appendChild(labeledField('Mesh', meshField));

			const materialField = document.createElement('input');
			materialField.type = 'text';
			materialField.value = model.material;
			materialField.disabled = true;
			body.appendChild(labeledField('Material', materialField));

			options.container.appendChild(section);
		}

		if (selected.rigidbody) {
			const rigidbody = selected.rigidbody;
			const { section, body } = createSection('Rigidbody');

			const kindField = document.createElement('select');
			for (const value of ['STATIC', 'DYNAMIC'] as const) {
				const optionEl = document.createElement('option');
				optionEl.value = value;
				optionEl.textContent = value;
				kindField.appendChild(optionEl);
			}
			kindField.value = rigidbody.kind;
			kindField.addEventListener('change', () => {
				setRigidbody(selected.id, { kind: kindField.value as 'STATIC' | 'DYNAMIC' });
			});
			body.appendChild(labeledField('Kind', kindField));

			const densityField = document.createElement('input');
			densityField.type = 'number';
			densityField.value = rigidbody.density !== undefined ? String(rigidbody.density) : '';
			densityField.addEventListener('input', () => {
				const density = parseFloat(densityField.value);
				if (!Number.isNaN(density)) setRigidbody(selected.id, { density });
			});
			body.appendChild(labeledField('Density', densityField));

			body.appendChild(
				createAxisRow({
					values: { ...rigidbody.half_extent },
					onChange: (axis, value) =>
						setRigidbody(selected.id, {
							half_extent: { ...rigidbody.half_extent, [axis]: value },
						}),
				})
			);

			options.container.appendChild(section);
		}

		// ---- add component ------------------------------------------------------
		const missingTypes = COMPONENT_TYPES.filter((type) => !selected[type]);
		if (missingTypes.length > 0) {
			const addRow = document.createElement('div');
			addRow.className = 'add-component-row';

			const typeSelect = document.createElement('select');
			for (const type of missingTypes) {
				const optionEl = document.createElement('option');
				optionEl.value = type;
				optionEl.textContent = type;
				typeSelect.appendChild(optionEl);
			}

			const addButton = document.createElement('button');
			addButton.type = 'button';
			addButton.textContent = 'Add Component';
			addButton.addEventListener('click', () => {
				addComponent(selected.id, typeSelect.value as ComponentType);
			});

			addRow.appendChild(typeSelect);
			addRow.appendChild(addButton);
			options.container.appendChild(addRow);
		}
	}

	render();
	subscribe(render);
}
