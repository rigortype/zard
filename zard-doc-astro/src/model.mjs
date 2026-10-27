import { parseLens } from './lens.mjs';

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
  if (span.end_line != null && (!Number.isInteger(span.end_line) || span.end_line < span.start_line)) fail('invalid source end line');
  return { path, line: span.start_line, endLine: span.end_line ?? span.start_line };
}
function declaration(value, revision) {
  const row = object(value, 'declaration');
  const kinds = ['class', 'module', 'constant', 'refinement', 'instance_method', 'singleton_method',
    ...['instance', 'singleton'].flatMap((scope) => ['reader', 'writer', 'accessor'].map((kind) => `${scope}_attribute_${kind}`))];
  if (!kinds.includes(row.kind)) fail(`unsupported declaration kind ${row.kind}`);
  const anchor = text(row.anchor, 'anchor');
  if (!/^zard-[0-9a-f]+$/.test(anchor)) fail('invalid declaration anchor');
  if (!['public', 'protected', 'private'].includes(row.visibility)) fail('invalid Ruby visibility');
  if (revision === 1 && row.visibility !== 'public') fail('non-public declaration in revision 1');
  const publication = revision === 1 ? 'public' : row.publication;
  if (!['public', 'internal'].includes(publication)) fail('invalid documentation publication intent');
  const tags = list(row.documentation, 'documentation').map((entry) => {
    object(entry, 'documentation tag');
    const line = sourceSpan(entry.span).line;
    if (!Number.isInteger(entry.span.end_line) || entry.span.end_line < line) fail('invalid documentation line range');
    return { name: text(entry.name, 'tag name'), subject: entry.subject == null ? null : text(entry.subject, 'tag subject'),
      description: text(entry.rendered_description, 'rendered description'),
      line, endLine: entry.span.end_line };
  });
  const parameterDetails = row.parameter_details == null ? null : list(row.parameter_details, 'parameter details').map((item) => {
    object(item, 'parameter detail');
    const kinds = ['required', 'optional', 'rest', 'post', 'required_keyword', 'optional_keyword', 'keyword_rest', 'block', 'forwarding', 'no_keywords', 'implicit_rest'];
    if (!kinds.includes(item.kind)) fail('unsupported parameter kind');
    sourceSpan(item.span);
    if (item.default != null) { text(item.default, 'parameter default'); sourceSpan(item.default_span); }
    return { kind: item.kind, source: text(item.source, 'parameter source') };
  });
  return { id: text(row.id, 'declaration id'), kind: text(row.kind, 'kind'), name: text(row.name, 'name'),
    displayName: text(row.display_name, 'display name'), page: outputPath(row.page), anchor,
    parameters: list(row.parameters, 'parameters').map((item) => text(item, 'parameter')),
    parameterDetails, visibility: row.visibility, publication,
    containerBuilder: row.container_builder == null ? null : text(row.container_builder, 'container builder'),
    relationships: row.relationships == null ? null : list(row.relationships, 'relationships').map((relationship) => {
      object(relationship, 'relationship');
      if (!['superclass', 'include', 'prepend', 'extend', 'container_builder'].includes(relationship.kind)) fail('unknown relationship kind');
      if (!['resolved', 'unresolved', 'expression'].includes(relationship.status)) fail('unknown relationship status');
      const targets = list(relationship.targets, 'relationship targets').map((target) => ({
        scope: text(target.scope, 'target scope'), id: text(target.declaration_id, 'target declaration id'),
        path: outputPath(target.path), anchor: text(target.anchor, 'target anchor'),
      }));
      if ((relationship.status === 'resolved') !== (targets.length > 0)) fail('relationship status contradicts targets');
      return {kind: relationship.kind, expression: text(relationship.expression, 'relationship expression'),
        source: sourceSpan(relationship.span), status: relationship.status, targets};
    }),
    source: sourceSpan(row.span), tags };
}

export function parseExport(value) {
  const data = object(value, 'document');
  if (data.schema !== 'zard-doc/v0' || ![1, 2].includes(data.revision)) fail(`unsupported schema/revision ${data.schema}/${data.revision}`);
  const producer = object(data.producer, 'producer');
  if (!['namespace', 'file'].includes(data.layout)) fail('unsupported documentation layout');
  const scopes = list(data.scopes, 'scopes').map((value) => {
    const scope = object(value, 'scope');
    const name = text(scope.name, 'scope name');
    const destination = outputPath(scope.destination);
    const declarations = list(scope.declarations, 'declarations').map((row) => declaration(row, data.revision));
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
    return { name, destination, pages, declarations, references: list(scope.references || [], 'scope references').map((name) => text(name, 'dependency scope')) };
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
  return { layout: data.layout, scopes, lens: parseLens(data.lens, scopes), producer: { zard: text(producer.zard, 'ZARD version'), zardDoc: text(producer.zard_doc, 'zard-doc version') } };
}
