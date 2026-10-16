const compareText = (a, b) => a < b ? -1 : a > b ? 1 : 0;

// Use code-unit ordering so builds and browsers agree regardless of locale.
export function compareMembers(a, b, order = 'definition') {
  return (order === 'name' ? compareText(a.name, b.name) : 0)
    || compareText(a.path, b.path) || a.line - b.line || compareText(a.anchor, b.anchor);
}

export function enhanceMembers(root = document) {
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
