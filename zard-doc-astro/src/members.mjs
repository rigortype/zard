const compareText = (a, b) => a < b ? -1 : a > b ? 1 : 0;

// Use code-unit ordering so builds and browsers agree regardless of locale.
export function compareMembers(a, b, order = 'definition') {
  return (order === 'name' ? compareText(a.name, b.name) : 0)
    || compareText(a.path, b.path) || a.line - b.line || compareText(a.anchor, b.anchor);
}

export function enhanceMembers(root = document) {
  for (const controls of root.querySelectorAll('.api-publication-controls')) {
    if (controls.dataset.apiReady) continue;
    controls.dataset.apiReady = 'true';
    const visibility = controls.querySelector('[data-api-visibility-filter]');
    const internal = controls.querySelector('[data-api-internal-filter]');
    const rows = [...root.querySelectorAll('[data-api-publication][data-api-visibility]')];
    const status = controls.querySelector('[data-api-filter-status]');
    const apply = () => {
      for (const row of rows) {
        row.hidden = (visibility.value !== 'all' && row.dataset.apiVisibility !== visibility.value)
          || (!internal.checked && row.dataset.apiPublication === 'internal');
      }
      const entries = rows.filter((row) => row.classList.contains('api-declaration'));
      const count = entries.length ? entries : rows;
      status.textContent = `${count.filter((row) => !row.hidden).length} of ${count.length} published declarations shown.`;
    };
    const view = root.ownerDocument?.defaultView ?? root.defaultView;
    const revealTarget = () => {
      const anchor = view?.location.hash.slice(1);
      const target = rows.find((row) => row.querySelector('[id]')?.id === anchor);
      if (!target) return;
      if (target.hidden) {
        visibility.value = 'all';
        internal.checked = true;
        apply();
      }
      if (target.tagName === 'DETAILS') target.open = true;
    };
    view?.addEventListener('hashchange', revealTarget);
    visibility.addEventListener('change', apply);
    internal.addEventListener('change', apply);
    controls.hidden = false;
    apply();
    revealTarget();
  }
  for (const select of root.querySelectorAll('[data-api-member-order]')) {
    if (select.dataset.apiReady) continue;
    select.dataset.apiReady = 'true';
    select.value = 'definition';
    select.addEventListener('change', () => {
      for (const list of root.querySelectorAll('[data-api-member-list]')) {
        const rows = [...list.children];
        const metadata = (row) => ({name: row.dataset.apiName, path: row.dataset.apiPath,
          line: Number(row.dataset.apiLine), anchor: row.dataset.apiAnchor});
        rows.sort((a, b) => compareMembers(metadata(a), metadata(b), select.value));
        list.append(...rows);
      }
    });
    select.closest('.api-member-controls').hidden = false;
  }
}
