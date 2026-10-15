import { code, escapeHtml } from './prose.mjs';
import { pageUrl } from './routes.mjs';

const identity = (scope, name) => JSON.stringify([scope, name]);
const fail = (message) => { throw new Error(`Invalid ZARD API relationships: ${message}`); };
const link = (row, basePath, label = row.displayName) => `<a class="api-index-link" href="${escapeHtml(`${pageUrl(row.page, basePath)}#${row.anchor}`)}">${code(label)}</a>`;

export function relationshipIndex(scopes) {
  const rows = new Map(scopes.flatMap((scope) => scope.declarations.map((row) => [row.id, {row, scope}])));
  const incoming = new Map();
  const entities = new Map();
  const diagnostics = [];
  for (const scope of scopes) for (const row of scope.declarations) {
    if (['class', 'module'].includes(row.kind)) {
      const key = identity(scope.name, row.displayName);
      if (!entities.has(key)) entities.set(key, {key, scope, name: row.displayName, rows: [], parents: new Set(), uncertain: false});
      entities.get(key).rows.push(row);
    }
  }
  for (const scope of scopes) for (const row of scope.declarations) for (const relationship of row.relationships || []) {
    if (!['class', 'module'].includes(row.kind)) fail('relationship source is not a container');
    const entity = entities.get(identity(scope.name, row.displayName));
    if (relationship.kind === 'superclass' && relationship.status !== 'resolved') entity.uncertain = true;
    for (const target of relationship.targets) {
      const found = rows.get(target.id);
      if (!found || found.scope.name !== target.scope || found.row.page !== target.path || found.row.anchor !== target.anchor) fail('missing relationship target');
      if (target.scope !== scope.name && !scope.references.includes(target.scope)) fail('relationship outside direct documentation dependencies');
      const expected = relationship.kind === 'superclass' ? 'class' : 'module';
      if (found.row.kind !== expected || relationship.kind === 'container_builder') fail('invalid relationship target kind');
      if (!incoming.has(target.id)) incoming.set(target.id, []);
      incoming.get(target.id).push({row, kind:relationship.kind});
      if (relationship.kind === 'superclass') entity.parents.add(identity(target.scope, found.row.displayName));
    }
  }
  for (const entity of entities.values()) {
    if (entity.rows.some((row) => row.kind !== entity.rows[0].kind)) {
      entity.uncertain = true;
      diagnostics.push(`Conflicting class/module declarations for ${entity.scope.name}:${entity.name}`);
    }
    if (entity.parents.size > 1) {
      entity.uncertain = true;
      diagnostics.push(`Conflicting written superclass references for ${entity.scope.name}:${entity.name}`);
    }
    if (!entity.uncertain && entity.parents.size === 1) entity.parent = [...entity.parents][0];
  }
  const done = new Set();
  for (const start of entities.keys()) {
    const path = [];
    const seen = new Map();
    let current = start;
    while (current && !done.has(current) && !seen.has(current)) {
      seen.set(current, path.length);
      path.push(current);
      current = entities.get(current)?.parent;
    }
    if (seen.has(current)) {
      const cycle = path.slice(seen.get(current));
      diagnostics.push(`Cycle in written superclass references: ${cycle.map((key) => entities.get(key).name).join(' → ')}`);
      for (const key of cycle) { entities.get(key).cycle = true; delete entities.get(key).parent; }
    }
    for (const key of path) done.add(key);
  }
  return {rows, incoming, entities, diagnostics};
}

export function renderRelationships(row, index, basePath) {
  const outgoing = row.relationships || [];
  const incoming = index.incoming.get(row.id) || [];
  if (!outgoing.length && !incoming.length) return '';
  let content = '<dl class="api-relationships">';
  for (const relationship of outgoing) {
    const label = relationship.kind === 'superclass' ? 'Superclass written in source' : relationship.kind.replaceAll('_', ' ');
    const targets = relationship.targets.map((target) => {
      const definition = index.rows.get(target.id).row;
      return link(definition, basePath, `${definition.source.path}:${definition.source.line}`);
    });
    content += `<dt>${escapeHtml(label)}</dt><dd>${code(relationship.expression)} — ${targets.length ? targets.join(', ') : escapeHtml(relationship.status === 'expression' ? 'source expression; no parent inferred' : 'documentation target unresolved')} <span class="api-meta">(${escapeHtml(`${relationship.source.path}:${relationship.source.line}`)})</span></dd>`;
  }
  const seen = new Set();
  for (const entry of incoming) {
    const key = `${entry.row.id}:${entry.kind}`;
    if (seen.has(key)) continue;
    seen.add(key);
    content += `<dt>${entry.kind === 'superclass' ? 'Known documented subclass' : `Documented ${entry.kind} user`}</dt><dd>${link(entry.row, basePath)} <span class="api-meta">${escapeHtml(`${entry.row.source.path}:${entry.row.source.line}`)}</span></dd>`;
  }
  return `${content}</dl>\n\n`;
}

export function renderHierarchy(scope, index, basePath) {
  const local = [...index.entities.values()].filter((entity) => entity.scope === scope);
  const classes = local.filter((entity) => entity.rows[0].kind === 'class');
  const children = new Map();
  const roots = [];
  for (const entity of classes) {
    if (!entity.parent || index.entities.get(entity.parent)?.scope !== scope) roots.push(entity);
    else {
      if (!children.has(entity.parent)) children.set(entity.parent, []);
      children.get(entity.parent).push(entity);
    }
  }
  const sort = (values) => values.sort((a, b) => a.name.localeCompare(b.name, 'en'));
  let content = 'These are relationships written in the documented sources. They do not establish effective runtime ancestry or inherited member ownership.\n\n## Class hierarchy\n\n';
  content += classes.length ? '<ul class="api-hierarchy">' : 'No documented classes.\n';
  const stack = sort(roots).reverse().map((entity) => ({entity}));
  while (stack.length) {
    const item = stack.pop();
    if (item.close) { content += '</ul></li>'; continue; }
    const entity = item.entity;
    content += `<li>${entity.rows.map((row) => link(row, basePath, `${row.displayName} (${row.source.path}:${row.source.line})`)).join(', ')}`;
    if (entity.cycle) content += ' — cycle; hierarchy not expanded';
    else if (entity.uncertain) content += ' — unresolved or conflicting superclass references';
    else if (entity.parent && index.entities.get(entity.parent)?.scope !== scope) content += ` — superclass in ${escapeHtml(index.entities.get(entity.parent).scope.name)}: ${link(index.entities.get(entity.parent).rows[0], basePath)}`;
    const descendants = children.get(entity.key) || [];
    if (descendants.length) {
      content += '<ul>';
      stack.push({close:true}, ...sort(descendants).reverse().map((entity) => ({entity})));
    } else content += '</li>';
  }
  if (classes.length) content += '</ul>\n';
  content += '\n## Module usage\n\n';
  const modules = sort(local.filter((entity) => entity.rows[0].kind === 'module'));
  if (!modules.length) content += 'No documented modules.\n';
  for (const entity of modules) {
    content += `<p>${entity.rows.map((row) => link(row, basePath, `${row.displayName} (${row.source.path}:${row.source.line})`)).join(', ')}</p><ul>`;
    const users = new Map(entity.rows.flatMap((row) => index.incoming.get(row.id) || []).map((entry) => [`${entry.kind}:${entry.row.id}`, entry]));
    for (const {row, kind} of users.values()) content += `<li>${escapeHtml(kind)}: ${link(row, basePath)}</li>`;
    content += users.size ? '</ul>\n' : '<li>No documented include, prepend or extend users.</li></ul>\n';
  }
  return content;
}
