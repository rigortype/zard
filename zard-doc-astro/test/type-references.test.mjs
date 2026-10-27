import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { createReference } from '../src/index.mjs';
import { parseTypeReferences, renderSignature } from '../src/type-references.mjs';

// Real zard-doc + Rigor 0.4.5 output over test/fixtures/rigor_lens/type_references.
const load = (name) => JSON.parse(readFileSync(new URL(`fixtures/${name}`, import.meta.url), 'utf8'));
const exports = { namespace: () => load('type-references-export.json'), file: () => load('type-references-file-export.json') };
const escape = (text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const signatures = (reference) => reference.pages.flatMap((page) => [...page.body.matchAll(/<pre class="api-lens-signature"><code>(.*?)<\/code><\/pre>/g)].map((match) => match[1]));
const linked = (html) => [...html.matchAll(/<a href="([^"]+)">([^<]+)<\/a>/g)].map((match) => ({ href: match[1], name: match[2] }));
const referencesNamed = (data, name) => data.lens.bindings.flatMap((binding) => binding.type_references.filter((item) => item.name === name).map((item) => ({ binding, item })));

for (const [layout, fixture] of Object.entries(exports)) {
  test(`${layout} layout links each uniquely resolved type to a rendered declaration anchor`, () => {
    const data = fixture();
    assert.equal(data.layout, layout);
    const reference = createReference(data, { basePath: 'apiref' });
    const links = signatures(reference).flatMap(linked);
    const resolved = data.lens.bindings.flatMap((binding) => binding.type_references).filter((item) => item.status === 'resolved');
    assert.equal(links.length, resolved.length);
    for (const link of links) {
      const [path, anchor] = link.href.split('#');
      const page = reference.pages.find((page) => `/${page.slug}/` === path);
      assert.ok(page, `missing route ${path}`);
      assert.ok(page.body.includes(`id="${anchor}"`), `missing anchor ${link.href}`);
    }
    const foo = links.filter((link) => link.name === '::App::Foo').map((link) => link.href);
    assert.equal(new Set(foo).size, 1);
    assert.ok(foo[0].startsWith(layout === 'file' ? '/apiref/app/reopened/#' : '/apiref/app/app/foo/#'));
    assert.ok(links.some((link) => link.name === 'App::Foo'), 'inferred return');
    assert.ok(links.some((link) => link.name === '::Shared::Thing' && link.href.startsWith('/apiref/shared/')));
    assert.ok(links.some((link) => link.name === '::Far' && link.href.startsWith('/apiref/far/')), 'direct dependency of shared');
  });

  test(`${layout} layout keeps every signature character and leaves other names literal`, () => {
    const data = fixture();
    const reference = createReference(data);
    const rendered = signatures(reference).map((html) => html.replace(/<a href="[^"]+">([^<]+)<\/a>/g, '$1'));
    const texts = data.lens.members.flatMap((member) => member.overloads.map((overload) => overload.rbs)).filter((text) => text != null);
    assert.deepEqual(new Set(rendered), new Set(texts.map(escape)));
    assert.ok(texts.some((text) => text.includes('"ä"')));
    const body = reference.pages.map((page) => page.body).join('\n');
    for (const name of ['::Twin', '::App::Hidden', '::Lonely', '::String', '::_ToS']) assert.ok(!body.includes(`">${name}</a>`), name);
    assert.ok(signatures(reference).some((html) => html === '() -&gt; T'));
    assert.match(body, /\[U\] \(U seed\) \{ \(T\) -&gt; U \}/);
    assert.deepEqual(reference.diagnostics.filter((message) => message.includes('type reference')), data.lens.warnings);
    assert.equal(data.lens.warnings.length, 2);
  });
}

test('legacy bindings without type metadata render literal signatures', () => {
  const data = exports.namespace();
  for (const binding of data.lens.bindings) { delete binding.type_references; delete binding.type_reference_diagnostics; }
  const reference = createReference(data);
  assert.ok(signatures(reference).length > 0);
  assert.ok(signatures(reference).every((html) => !html.includes('<a ')));
});

const rejections = {
  'ambiguous reference requires competing candidates': (data) => { referencesNamed(data, '::Twin')[0].item.candidates.pop(); },
  'resolved reference requires one candidate and one target': (data) => {
    const { item } = referencesNamed(data, '::Twin')[0];
    item.status = 'resolved';
  },
  'unresolved reference contradicts its reason': (data) => { referencesNamed(data, '::App::Hidden')[0].item.reason = 'missing'; },
  'only unresolved references carry a reason': (data) => { referencesNamed(data, '::Shared::Thing')[0].item.reason = 'missing'; },
  'candidate outside explicit documentation dependencies': (data) => {
    const far = referencesNamed(data, '::Far').find(({ binding }) => binding.scope === 'shared').item;
    const { item } = referencesNamed(data, '::Far').find(({ binding }) => binding.scope === 'app');
    Object.assign(item, { status: 'resolved', reason: undefined, candidates: far.candidates, targets: far.targets });
  },
  'target is not a candidate': (data) => { referencesNamed(data, '::Shared::Thing')[0].item.candidates[0].span.start_line += 1; },
  'target name mismatch': (data) => {
    const foo = referencesNamed(data, '::App::Foo')[0].item.targets[0];
    Object.assign(referencesNamed(data, '::App::Common')[0].item, { targets: [foo], candidates: [{ scope: foo.scope, span: foo.span }] });
  },
  'range does not match type name': (data) => { referencesNamed(data, '::App::Common')[0].item.end_offset -= 1; },
  'range splits a UTF-8 character': (data) => {
    const { item } = referencesNamed(data, '::App::Foo').find(({ item }) => item.start_offset > 80);
    const member = data.lens.members.find((member) => member.key === item.member_key);
    const bytes = new TextEncoder().encode(member.overloads[item.overload].rbs);
    item.end_offset = bytes.indexOf(0xc3) + 1;
  },
  'overlapping type references': (data) => {
    const { binding, item } = referencesNamed(data, '::App::Common')[0];
    binding.type_references.push({ ...item });
  },
  'target is not a visible documented declaration': (data) => { referencesNamed(data, '::Shared::Thing')[0].item.targets[0].anchor = 'zard-00'; },
};
for (const [message, mutate] of Object.entries(rejections)) {
  test(`rejects type metadata when ${message}`, () => {
    const data = exports.namespace();
    mutate(data);
    assert.throws(() => createReference(data), new RegExp(message.replace(/[()]/g, '\\$&')));
  });
}

test('renders the exact spelling of a resolved name with HTML escaping', () => {
  const key = JSON.stringify(['Box', 'instance', 'call']);
  const text = '(::Foo input) -> ::Foo';
  const source = { path: 'lib/foo.rb', start_line: 1, end_line: 3 };
  const target = { scope: 'app', declaration_id: 'app:foo', path: 'app/Foo.md', anchor: 'zard-666f6f', span: source };
  const scopes = [{ name: 'app', references: [], declarations: [{ id: target.declaration_id, kind: 'class', displayName: 'Foo',
    page: target.path, anchor: target.anchor, source: { path: 'lib/foo.rb', line: 1, endLine: 3 } }] }];
  const members = new Map([[key, { owner: 'Box', overloads: [{ rbs: text }] }]]);
  const binding = { scope: 'app', member_keys: [key], type_references: [
    { member_key: key, overload: 0, start_offset: 1, end_offset: 6, name: '::Foo', status: 'resolved', candidates: [{ scope: 'app', span: source }], targets: [target] },
  ] };
  const parsed = parseTypeReferences(binding, members, scopes);
  assert.equal(renderSignature(text, parsed.references, key, 0, 'apiref'), '(<a href="/apiref/app/foo/#zard-666f6f">::Foo</a> input) -&gt; ::Foo');
});
