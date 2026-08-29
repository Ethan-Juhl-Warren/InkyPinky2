// The left panel: a list of entities in the scene. Click one to select it.

import { getEntities, getSelectedId, select, subscribe } from "./sceneStub";

export interface HierarchyOptions {
  container: HTMLElement;
}

export function mountHierarchy(options: HierarchyOptions): void {

  function render(): void {
    options.container.innerHTML = '';
    const heirarchyList = document.createElement('ul');
    heirarchyList.className = 'tree';

    for (const entity of getEntities()) {
      const row = document.createElement('li');
      row.textContent = entity.name;
      heirarchyList.appendChild(row);
      row.addEventListener('click', () => {
        select(entity.id);
      });
      if (entity.id === getSelectedId()) {
        row.classList.add('selected'); // add another className =, for the css to hit
      }
    }
    options.container.appendChild(heirarchyList);
  }
  render();
  subscribe(render);
}
