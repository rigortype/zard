import { escapeHtml } from './prose.mjs';
import { pageUrl } from './routes.mjs';

const fail = (message) => { throw new Error(`Invalid ZARD lens type reference: ${message}`); };
const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });
const identity = (key, overload) => JSON.stringify([key, overload]);
const reasons = ['missing', 'unpublished', 'not_class_or_module'];
const sameSpan = (left, right) => left.path === right.path && left.start_line === right.start_line && left.end_line === right.end_line;

function span(value) {
  if (!value || typeof value !== 'object' || typeof value.path !== 'string' || !Number.isInteger(value.start_line) || !Number.isInteger(value.end_line) || value.end_line < value.start_line) fail('invalid source span');
  return value;
}

// Type names were found and resolved by the producer; this only checks that the metadata
// agrees with the signature text and the exported declarations before anything is linked.
export function parseTypeReferences(binding, members, scopes) {
  const references = binding.type_references ?? [];
  const diagnostics = binding.type_reference_diagnostics ?? [];
  if (!Array.isArray(references) || !Array.isArray(diagnostics) || diagnostics.some((value) => typeof value !== 'string')) fail('expected reference and diagnostic arrays');
  const origin = scopes.find((scope) => scope.name === binding.scope);
  const visible = new Set([origin.name, ...origin.references]);
  const grouped = new Map();
  for (const reference of references) {
    if (!reference || typeof reference !== 'object') fail('expected reference object');
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
    if (!['resolved', 'unresolved', 'ambiguous'].includes(reference.status) || !Array.isArray(reference.targets) || !Array.isArray(reference.candidates)) fail('invalid resolution status');
    const candidates = reference.candidates.map((candidate) => {
      if (!visible.has(candidate?.scope)) fail('candidate outside explicit documentation dependencies');
      return { scope: candidate.scope, span: span(candidate.span) };
    });
    const count = candidates.length;
    if (reference.status === 'resolved' && (count !== 1 || reference.targets.length !== 1)) fail('resolved reference requires one candidate and one target');
    if (reference.status === 'ambiguous' && count < 2) fail('ambiguous reference requires competing candidates');
    if (reference.status === 'unresolved' && (reference.targets.length || !reasons.includes(reference.reason) || count !== (reference.reason === 'missing' ? 0 : 1))) fail('unresolved reference contradicts its reason');
    if (reference.status !== 'unresolved' && reference.reason != null) fail('only unresolved references carry a reason');
    const name = reference.name.replace(/^::/, '');
    const targets = reference.targets.map((target) => {
      const scope = scopes.find((scope) => scope.name === target?.scope);
      const row = scope?.declarations.find((row) => row.id === target.declaration_id);
      const typed = row && (['class', 'module'].includes(row.kind) || (row.kind === 'constant' && row.containerBuilder != null));
      if (!visible.has(target.scope) || !typed || row.page !== target.path || row.anchor !== target.anchor) fail('target is not a visible documented declaration');
      if (!sameSpan(span(target.span), { path: row.source.path, start_line: row.source.line, end_line: row.source.endLine })) fail('target source location mismatch');
      if (!candidates.some((candidate) => candidate.scope === target.scope && sameSpan(candidate.span, target.span))) fail('target is not a candidate');
      if (row.displayName.replace(/^::/, '') !== name) fail('target name mismatch');
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

// Only a uniquely resolved name becomes a link; every character of the signature is kept.
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
