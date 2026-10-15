const fail = (message) => { throw new Error(`Invalid ZARD API export: ${message}`); };
const object = (value, label) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`${label} must be an object`);
  return value;
};
const list = (value, label) => {
  if (!Array.isArray(value)) fail(`${label} must be an array`);
  return value;
};
const text = (value, label) => {
  if (typeof value !== 'string' || value.includes('\0')) fail(`${label} must be text`);
  return value;
};
const unique = (values, label) => {
  if (new Set(values).size !== values.length) fail(`duplicate ${label}`);
};
export function outputPath(value) {
  text(value, 'output path');
  if (!value || value.includes('\\') || value.split('/').some((part) => ['', '.', '..'].includes(part))) fail('unsafe output path');
  return value;
}
function sourceSpan(value) {
  const span = object(value, 'source span');
  const path = text(span.path, 'source path');
  if (!path || path.startsWith('/') || /^[A-Za-z]:/.test(path) || path.includes('\\')) fail('absolute or invalid source path');
  if (!Number.isInteger(span.start_line) || span.start_line < 1) fail('invalid source line');
  return { path, line: span.start_line };
}
function declaration(value) {
  const row = object(value, 'declaration');
  const kinds = ['class', 'module', 'constant', 'refinement', 'instance_method', 'singleton_method',
    ...['instance', 'singleton'].flatMap((scope) => ['reader', 'writer', 'accessor'].map((kind) => `${scope}_attribute_${kind}`))];
  if (!kinds.includes(row.kind)) fail(`unsupported declaration kind ${row.kind}`);
  const anchor = text(row.anchor, 'anchor');
  if (!/^zard-[0-9a-f]+$/.test(anchor)) fail('invalid declaration anchor');
  if (row.visibility !== 'public') fail('non-public declaration');
  const tags = list(row.documentation, 'documentation').map((entry) => {
    object(entry, 'documentation tag');
    const line = sourceSpan(entry.span).line;
    if (!Number.isInteger(entry.span.end_line) || entry.span.end_line < line) fail('invalid documentation line range');
    return { name: text(entry.name, 'tag name'), subject: entry.subject == null ? null : text(entry.subject, 'tag subject'),
      description: text(entry.rendered_description, 'rendered description'),
      line, endLine: entry.span.end_line };
  });
  return { id: text(row.id, 'declaration id'), kind: text(row.kind, 'kind'), name: text(row.name, 'name'),
    displayName: text(row.display_name, 'display name'), page: outputPath(row.page), anchor,
    parameters: list(row.parameters, 'parameters').map((item) => text(item, 'parameter')),
    source: sourceSpan(row.span), tags };
}

export function parseExport(value) {
  const data = object(value, 'document');
  if (data.schema !== 'zard-doc/v0' || data.revision !== 1) fail(`unsupported schema/revision ${data.schema}/${data.revision}`);
  const producer = object(data.producer, 'producer');
  if (data.layout !== 'namespace') fail('the site currently requires namespace layout');
  const scopes = list(data.scopes, 'scopes').map((value) => {
    const scope = object(value, 'scope');
    const name = text(scope.name, 'scope name');
    const destination = outputPath(scope.destination);
    const declarations = list(scope.declarations, 'declarations').map(declaration);
    unique(declarations.map((row) => row.id), 'declaration id');
    const byId = new Map(declarations.map((row) => [row.id, row]));
    const pages = list(scope.pages, 'pages').map((value) => {
      const page = object(value, 'page');
      const path = outputPath(page.path);
      if (!path.startsWith(`${destination}/`) || !path.endsWith('.md')) fail('page outside scope destination');
      const ids = list(page.declarations, 'page declaration ids').map((id) => text(id, 'id'));
      unique(ids, 'page declaration id');
      const rows = ids.map((id) => {
        const row = byId.get(id);
        if (!row || row.page !== path) fail(`unmatched declaration ${id}`);
        return row;
      });
      unique(rows.map((row) => row.anchor), 'page anchor');
      return { path, declarations: rows };
    });
    unique(pages.map((page) => page.path), 'page path');
    if (pages.reduce((count, page) => count + page.declarations.length, 0) !== declarations.length) fail('declaration missing from pages');
    return { name, destination, pages, declarations };
  });
  unique(scopes.map((scope) => scope.name), 'scope name');
  unique(scopes.flatMap((scope) => scope.declarations.map((row) => row.id)), 'global declaration id');
  const pages = scopes.flatMap((scope) => scope.pages);
  unique(pages.map((page) => page.path), 'global page path');
  const byPath = new Map(pages.map((page) => [page.path, page]));
  for (const [from, targets] of Object.entries(object(data.links, 'links'))) {
    if (!byPath.has(from)) fail('unknown link source');
    for (const target of list(targets, 'link targets')) {
      object(target, 'link target');
      const page = byPath.get(target.path);
      if (!page?.declarations.some((row) => row.anchor === target.anchor)) fail('link to missing declaration');
    }
  }
  return { scopes, producer: { zard: text(producer.zard, 'ZARD version'), zardDoc: text(producer.zard_doc, 'zard-doc version') } };
}
