import { escapeHtml } from './prose.mjs';
import { pageUrl } from './routes.mjs';

const fail = (message) => { throw new Error(`Invalid ZARD lens type reference: ${message}`); };
const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });
const identity = (key, overload) => JSON.stringify([key, overload]);

export function parseTypeReferences(binding, members, scopes) {
  const references = binding.type_references ?? [];
  const diagnostics = binding.type_reference_diagnostics ?? [];
  if (!Array.isArray(references) || !Array.isArray(diagnostics) || diagnostics.some((value) => typeof value !== 'string')) fail('expected reference and diagnostic arrays');
  const origin = scopes.find((scope) => scope.name === binding.scope);
  const visible = new Set([origin.name, ...origin.references]);
  const grouped = new Map();
  for (const reference of references) {
    const member = members.get(reference.member_key);
    if (!binding.member_keys.includes(reference.member_key) || !member || !Number.isInteger(reference.overload) || reference.overload < 0) fail('unknown bound signature');
    const text = member.overloads[reference.overload]?.rbs;
    if (typeof text !== 'string') fail('missing signature text');
    const bytes = encoder.encode(text);
    const { start_offset: first, end_offset: last } = reference;
    if (!Number.isInteger(first) || !Number.isInteger(last) || first < 0 || last <= first || last > bytes.length) fail('invalid signature range');
    let start, end;
    try {
      start = decoder.decode(bytes.subarray(0, first)).length;
      end = decoder.decode(bytes.subarray(0, last)).length;
    } catch { fail('range splits a UTF-8 character'); }
    if (typeof reference.name !== 'string' || text.slice(start, end) !== reference.name) fail('range does not match type name');
    if (!['resolved', 'unresolved', 'ambiguous'].includes(reference.status) || !Array.isArray(reference.targets)) fail('invalid resolution status');
    if (reference.status === 'resolved' && reference.targets.length !== 1) fail('resolved reference requires one target');
    if (reference.status === 'unresolved' && reference.targets.length) fail('unresolved reference has targets');
    const targets = reference.targets.map((target) => {
      const scope = scopes.find((scope) => scope.name === target.scope);
      const row = scope?.declarations.find((row) => row.id === target.declaration_id);
      if (!visible.has(target.scope) || !row || !['class', 'module'].includes(row.kind) || row.page !== target.path || row.anchor !== target.anchor) fail('target is not a visible documented declaration');
      if (target.span?.path !== row.source.path || target.span.start_line !== row.source.line || target.span.end_line !== row.source.endLine) fail('target source location mismatch');
      const name = reference.name.replace(/^::/, '');
      const parts = member.owner.replace(/^::/, '').split('::');
      const names = reference.name.startsWith('::') ? [name] : Array.from({ length: parts.length + 1 }, (_, index) => [...parts.slice(0, parts.length - index), name].join('::'));
      if (!names.includes(row.displayName.replace(/^::/, ''))) fail('target name mismatch');
      return target;
    });
    if (new Set(targets.map((target) => target.declaration_id)).size !== targets.length) fail('duplicate targets');
    const key = identity(reference.member_key, reference.overload);
    const entries = grouped.get(key) || [];
    entries.push({ start, end, status: reference.status, targets });
    grouped.set(key, entries);
  }
  for (const entries of grouped.values()) {
    entries.sort((left, right) => left.start - right.start);
    if (entries.some((entry, index) => index > 0 && entry.start < entries[index - 1].end)) fail('overlapping type references');
  }
  return { references: grouped, diagnostics };
}

export function renderSignature(text, references, memberKey, overload, basePath) {
  let output = '', position = 0;
  for (const reference of references?.get(identity(memberKey, overload)) || []) {
    output += escapeHtml(text.slice(position, reference.start));
    const name = escapeHtml(text.slice(reference.start, reference.end));
    const target = reference.targets[0];
    output += reference.status === 'resolved'
      ? `<a href="${escapeHtml(`${pageUrl(target.path, basePath)}#${target.anchor}`)}">${name}</a>` : name;
    position = reference.end;
  }
  return output + escapeHtml(text.slice(position));
}
