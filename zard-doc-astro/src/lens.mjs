import { code, escapeHtml } from './prose.mjs';
import compatibility from './lens-compatibility.json' with { type: 'json' };

const fail = (message) => { throw new Error(`Invalid ZARD lens data: ${message}`); };
const array = (value) => { if (!Array.isArray(value)) fail('expected array'); return value; };
const slot = (value) => {
  if (!value || !['typed', 'dynamic', 'unavailable'].includes(value.state)) fail('unknown slot state');
  if (value.state === 'unavailable') {
    if (!['contested', 'not_computed', 'definition_build_failed'].includes(value.reason)) fail('unknown unavailable reason');
  } else {
    if (typeof value.type !== 'string' || typeof value.provenance !== 'string') fail('missing type/provenance');
    if (value.state === 'dynamic' && value.type !== 'untyped') fail('dynamic slot must be untyped');
  }
};

export function parseLens(data, scopes) {
  if (data == null) return null;
  if (data.schema !== compatibility.schema || data.revision !== compatibility.revision || data.producer?.name !== compatibility.producer || !compatibility.versions.includes(data.producer?.version)) fail('unsupported producer/schema/revision');
  const declarations = new Map(scopes.flatMap((scope) => scope.declarations.map((row) => [row.id, scope.name])));
  const sites = new Map();
  for (const file of array(data.files)) {
    for (const site of file.sites || []) {
      if (sites.has(site.key) || typeof site.key !== 'string') fail('duplicate/invalid site key');
      if (site.body_return) slot(site.body_return);
      sites.set(site.key, { ...site, path: file.path });
    }
  }
  const members = new Map();
  for (const member of array(data.members)) {
    if (member.key !== JSON.stringify([member.owner, member.scope, member.name]) || members.has(member.key)) fail('invalid member identity');
    if (!['contract', 'single_site', 'contested'].includes(member.basis)) fail('unknown member basis');
    if (!array(member.sites).every((key) => sites.has(key))) fail('missing member site');
    if (member.basis === 'contested' && array(member.overloads).length) fail('contested member has overloads');
    for (const overload of array(member.overloads)) {
      if (overload.rbs != null && typeof overload.rbs !== 'string') fail('invalid RBS text');
      for (const parameter of overload.params || []) slot(parameter.type);
      if (overload.block) slot(overload.block.type);
      slot(overload.return);
      for (const value of [...(overload.params || []).map((row) => row.type), overload.block?.type, overload.return]) {
        if (value?.from_site && !member.sites.includes(value.from_site)) fail('missing inferred origin');
      }
    }
    members.set(member.key, member);
  }
  const bindings = new Map();
  for (const binding of array(data.bindings)) {
    if (!declarations.has(binding.declaration_id) || declarations.get(binding.declaration_id) !== binding.scope || bindings.has(binding.declaration_id)) fail('invalid declaration binding');
    if (!['matched', 'unavailable'].includes(binding.status)) fail('unknown binding status');
    if (binding.status === 'matched' && !sites.has(binding.site_key)) fail('missing bound site');
    if (binding.status === 'unavailable' && (binding.site_key != null || typeof binding.reason !== 'string')) fail('invalid unavailable binding');
    for (const field of ['file', 'capability', 'detail']) {
      if (binding[field] != null && typeof binding[field] !== 'string') fail('invalid binding explanation');
    }
    if (binding.omission && (typeof binding.omission.kind !== 'string' || typeof binding.omission.reason !== 'string')) fail('invalid omission explanation');
    for (const key of array(binding.member_keys)) {
      if (!members.get(key)?.sites.includes(binding.site_key)) fail('missing bound member');
    }
    bindings.set(binding.declaration_id, binding);
  }
  if (bindings.size !== declarations.size) fail('declaration missing from bindings');
  return { bindings, sites, members, files: data.files, capabilities: array(data.capabilities), producer: data.producer, schema: data.schema, revision: data.revision };
}

const bindingReasons = {
  unsupported_declaration: 'This declaration uses a construct not supported by this lens version',
  unsupported_capability: 'The producer does not supply this declaration capability',
  unmatched_declaration: 'No matching source site was reported',
  not_reported: 'No matching source site was reported',
  ambiguous_site: 'Several source sites match; no site was selected',
  failed: 'The producer failed to analyze this file',
  parse_error: 'The producer could not parse this file',
  not_found: 'The requested source file was not found',
  not_ruby: 'The producer did not recognize a Ruby source file',
  outside_project: 'The source file is outside the configured analysis project',
  duplicate: 'The producer reported a duplicate target',
};

export function renderLensSummary(rows, lens) {
  if (!lens) return '';
  const missing = rows.filter((row) => lens.bindings.get(row.id).status === 'unavailable').length;
  const paths = new Set(rows.map((row) => lens.bindings.get(row.id).file || lens.sites.get(lens.bindings.get(row.id).site_key)?.path || row.source.path));
  const incomplete = lens.files.filter((file) => paths.has(file.path) && file.complete === false);
  const absent = ['body_return', 'diagnostics', 'inputs'].filter((capability) => !lens.capabilities.includes(capability));
  if (!missing && !incomplete.length && !absent.length) return '';
  let content = '<aside class="api-lens-summary" aria-label="Type information coverage"><p><strong>Type information coverage</strong></p><ul>';
  if (missing) content += `<li>${missing} of ${rows.length} declarations have no attached type information. Each declaration explains why.</li>`;
  for (const file of incomplete) content += `<li>${code(file.path)}: the producer omitted ${array(file.omissions).length} declarations or constructs. Source documentation remains available.</li>`;
  if (absent.length) content += `<li>Capabilities not supplied by this producer: ${absent.map(code).join(', ')}.</li>`;
  return `${content}</ul></aside>\n\n`;
}

const unavailable = { contested: 'multiple definitions', not_computed: 'not computed', definition_build_failed: 'definition could not be analyzed' };
const causes = { explicit_untyped: 'explicit untyped annotation', inferred_return_untyped: 'inferred return is untyped', external_gem_without_rbs: 'external gem without signatures', framework_dsl_boundary: 'framework DSL', analyzer_budget_cutoff: 'analysis budget', unsupported_syntax: 'unsupported syntax' };

function slotText(value, lens) {
  if (value.state === 'unavailable') return `Unavailable — ${escapeHtml(unavailable[value.reason])}`;
  let text = code(value.type);
  if (value.state === 'dynamic') text += ` (dynamic; ${escapeHtml(causes[value.cause] || value.cause || 'cause not reported')})`;
  text += ` — ${escapeHtml(value.provenance)}`;
  if (value.path) text += ` · ${code(value.path)}`;
  const origin = value.from_site && lens.sites.get(value.from_site);
  if (origin) text += ` · ${code(`${origin.path}:${origin.span.start_line}`)}`;
  return text;
}

export function renderLens(row, lens) {
  if (!lens) return '';
  const binding = lens.bindings.get(row.id);
  if (binding.status === 'unavailable') {
    let reason = bindingReasons[binding.reason] || binding.reason.replaceAll('_', ' ');
    if (binding.omission) reason += ` (${binding.omission.kind}: ${binding.omission.reason})`;
    if (binding.capability) reason += ` (${binding.capability})`;
    if (binding.detail) reason += `: ${binding.detail}`;
    return `<p class="api-lens-status">Rigor type information unavailable: ${escapeHtml(reason)}.</p>\n\n`;
  }
  const site = lens.sites.get(binding.site_key);
  if (!binding.member_keys.length && !site.body_return) return '';
  let content = '<aside class="api-lens" aria-label="Rigor type information">\n';
  for (const key of binding.member_keys) {
    const member = lens.members.get(key);
    const name = `${member.owner}${member.scope === 'singleton' ? '.' : '#'}${member.name}`;
    content += `<p><strong>Member signature ${code(name)}</strong><br>Shared across its definitions · ${escapeHtml(member.basis.replaceAll('_', ' '))} · visibility: ${escapeHtml(member.visibility || 'unknown')}</p>\n`;
    if (member.basis === 'contested') content += '<p>Signature unavailable: multiple definitions; no runtime winner is selected.</p>\n';
    for (const overload of member.overloads) {
      if (overload.rbs != null) content += `<pre class="api-lens-signature"><code>${escapeHtml(overload.rbs)}</code></pre>\n`;
      content += '<dl>\n';
      if (overload.params == null) content += '<dt>Parameters</dt><dd>Details unavailable</dd>\n';
      for (const parameter of overload.params || []) content += `<dt>Parameter ${code(parameter.name || '(anonymous)')} (${escapeHtml(parameter.kind)})</dt><dd>${slotText(parameter.type, lens)}</dd>\n`;
      if (overload.block) content += `<dt>Block (${overload.block.required ? 'required' : 'optional'})</dt><dd>${slotText(overload.block.type, lens)}</dd>\n`;
      content += `<dt>Returns</dt><dd>${slotText(overload.return, lens)}</dd></dl>\n`;
    }
  }
  if (site.body_return) content += `<p><strong>Body return for this definition</strong><br>${slotText(site.body_return, lens)}</p>\n`;
  return `${content}</aside>\n\n`;
}
