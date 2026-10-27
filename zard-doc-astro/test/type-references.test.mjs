import assert from 'node:assert/strict';
import test from 'node:test';
import { parseTypeReferences, renderSignature } from '../src/type-references.mjs';

const key = JSON.stringify(['Box', 'instance', 'call']);
const signature = '(::Foo input) -> ::Foo';
const target = { scope: 'app', declaration_id: 'app:foo', path: 'app/Foo.md', anchor: 'zard-666f6f',
  span: { path: 'lib/foo.rb', start_line: 1, end_line: 3 } };
const scopes = [{ name: 'app', references: [], declarations: [{ id: target.declaration_id, kind: 'class',
  displayName: 'Foo', page: target.path, anchor: target.anchor, source: { path: 'lib/foo.rb', line: 1, endLine: 3 } }] }];
const members = new Map([[key, { owner: 'Box', overloads: [{ rbs: signature }] }]]);
const binding = () => ({ scope: 'app', member_keys: [key], type_references: [
  { member_key: key, overload: 0, start_offset: 1, end_offset: 6, name: '::Foo', status: 'resolved', targets: [target] },
] });

test('renders the exact type spelling as a link to the documented route and anchor', () => {
  const parsed = parseTypeReferences(binding(), members, scopes);
  assert.equal(renderSignature(signature, parsed.references, key, 0, 'apiref'),
    '(<a href="/apiref/app/foo/#zard-666f6f">::Foo</a> input) -&gt; ::Foo');
});

test('legacy metadata and unresolved references preserve literal signature text', () => {
  const legacy = parseTypeReferences({ scope: 'app', member_keys: [key] }, members, scopes);
  assert.equal(renderSignature(signature, legacy.references, key, 0, 'apiref'), '(::Foo input) -&gt; ::Foo');
  const value = binding();
  Object.assign(value.type_references[0], { status: 'unresolved', targets: [] });
  const parsed = parseTypeReferences(value, members, scopes);
  assert.equal(renderSignature(signature, parsed.references, key, 0, 'apiref'), '(::Foo input) -&gt; ::Foo');
});

test('rejects mismatched ranges and targets outside explicit documentation dependencies', () => {
  const value = binding();
  value.type_references[0].end_offset = 5;
  assert.throws(() => parseTypeReferences(value, members, scopes), /range does not match/);
  const hidden = binding();
  hidden.type_references[0].targets = [{ ...target, scope: 'unrelated' }];
  assert.throws(() => parseTypeReferences(hidden, members, scopes), /visible documented declaration/);
});
