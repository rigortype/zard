import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { createReference } from '../src/index.mjs';

// Real zard-doc + Rigor 0.4.5 output over Rigor's pinned shared fixture.
const fixture = () => JSON.parse(readFileSync(new URL('fixtures/lens-export.json', import.meta.url), 'utf8'));

test('renders released constant facts and keeps module-function signatures separate', () => {
  const data = fixture();
  const reference = createReference(data);
  const shop = reference.pages.find((page) => page.slug === 'api/app/shop').body;
  assert.match(shop, /Constant value type/);
  const constant = data.lens.files.flatMap((file) => file.sites).find((site) => site.kind === 'constant');
  assert.ok(shop.includes(`<code>${constant.value.type}</code>`));
  const util = reference.pages.find((page) => page.slug === 'api/app/util').body;
  assert.match(util, /Member signature <code>Util.helper/);
  assert.doesNotMatch(util, /Member signature <code>Util#helper|Body return for this definition/);
  constant.value = {state:'guessed'};
  assert.throws(() => createReference(data), /unknown slot state/);
});

test('shows member facts, site body returns and unavailable/dynamic states without parsing types', () => {
  const data = fixture();
  const reference = createReference(data);
  const body = reference.pages.find((page) => page.slug === 'api/app/shop').body;
  assert.match(body, /Shared across its definitions/);
  assert.match(body, /Signature unavailable: multiple definitions/);
  assert.match(body, /Unavailable — multiple definitions/);
  assert.match(body, /Body return for this definition/);
  const order = reference.pages.find((page) => page.slug === 'api/app/order').body;
  assert.match(order, /untyped<\/code> \(dynamic/);
  for (const member of data.lens.members) {
    for (const overload of member.overloads) {
      if (overload.rbs) assert.ok(reference.pages.some((page) => page.body.includes(overload.rbs.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;'))));
    }
  }
  delete data.lens;
  assert.ok(createReference(data).pages.every((page) => !page.body.includes('api-lens')));
});

test('requires the supported type grammar only when lens data is present', () => {
  const data = fixture();
  assert.equal(data.lens.adapter.grammar, 'rigor:v1');
  assert.ok(createReference(data).pages.some((page) => page.body.includes('api-lens-signature')));
  for (const adapter of [undefined, null, {}, { grammar: null }, { grammar: 'rigor:v2' }]) {
    const incompatible = fixture();
    incompatible.lens.adapter = adapter;
    assert.throws(() => createReference(incompatible), /unsupported type grammar/);
  }
  delete data.lens;
  assert.ok(createReference(data).pages.every((page) => !page.body.includes('api-lens')));
});

test('rejects incompatible lens data and dangling joins instead of publishing guessed types', () => {
  const mutations = [
    (data) => { data.lens.revision = 2; },
    (data) => { data.lens.producer.version = '0.4.3'; },
    (data) => { data.lens.producer.version = '0.4.4'; },
    (data) => { data.lens.bindings[0].site_key = 'missing'; },
    (data) => { data.lens.bindings.pop(); },
    (data) => { data.lens.members[0].sites = ['missing']; },
    (data) => { data.lens.members.find((member) => member.overloads.length).overloads[0].return = { state: 'guessed' }; },
  ];
  for (const mutation of mutations) {
    const data = fixture(); mutation(data);
    assert.throws(() => createReference(data), /Invalid ZARD lens data/);
  }
});

test('explains target failures and missing capabilities without interpreting diagnostic HTML', () => {
  const data = fixture();
  const row = data.scopes[0].declarations.find((row) => row.name === 'label');
  const binding = data.lens.bindings.find((binding) => binding.declaration_id === row.id);
  Object.assign(binding, { status: 'unavailable', reason: 'failed', detail: '<script>failure</script>', site_key: null, member_keys: [] });
  data.lens.capabilities = data.lens.capabilities.filter((value) => value !== 'body_return');
  for (const file of data.lens.files) for (const site of file.sites || []) delete site.body_return;
  const body = createReference(data).pages.find((page) => page.slug === 'api/app/shop').body;
  assert.match(body, /producer failed to analyze this file: &lt;script&gt;failure&lt;\/script&gt;/);
  assert.match(body, /Capabilities not supplied by this producer: <code>body_return<\/code>/);
  assert.doesNotMatch(body, /Body return for this definition|<script>/);
});

const boundaries = () => JSON.parse(readFileSync(new URL('fixtures/lens-boundaries-export.json', import.meta.url), 'utf8'));
function declarationBody(reference, row) {
  const page = reference.pages.find((page) => page.body.includes(`id="${row.anchor}"`));
  assert.ok(page, `missing rendered definition ${row.display_name}`);
  const start = page.body.indexOf(`<h3 id="${row.anchor}"`);
  const closing = row.kind.includes('method') ? '</details>' : '</section>';
  const end = page.body.indexOf(closing, start);
  assert.ok(end > start);
  return page.body.slice(start, end);
}

test('released receiver and refinement omissions remain separate from same-named matched members', () => {
  const data = boundaries();
  const reference = createReference(data);
  const rows = data.scopes[0].declarations;
  const explicit = rows.find((row) => row.receiver === 'Target');
  const explicitBody = declarationBody(reference, explicit);
  assert.match(explicitBody, /construct not supported by this lens version \(method: unsupported_kind\)/);
  assert.doesNotMatch(explicitBody, /Member signature|Body return for this definition/);
  const selfMethods = rows.filter((row) => row.receiver === 'self');
  assert.equal(selfMethods.length, 2);
  for (const row of selfMethods) {
    const body = declarationBody(reference, row);
    assert.ok(body.includes(`Member signature <code>${row.namespace}.identity</code>`));
    assert.doesNotMatch(body, /type information unavailable/);
  }
  const refined = rows.filter((row) => row.refinement);
  assert.deepEqual(refined.map((row) => row.refinement), ['String', 'Integer']);
  assert.equal(new Set([...selfMethods, explicit, ...refined].map((row) => row.anchor)).size, 5);
  for (const row of refined) {
    const body = declarationBody(reference, row);
    assert.match(body, /No matching source site was reported/);
    assert.doesNotMatch(body, /Member signature|Body return for this definition/);
  }
  for (const row of rows.filter((row) => row.kind === 'refinement')) {
    assert.match(declarationBody(reference, row), /producer does not supply this declaration capability \(refinement\)/);
  }
});

test('released overloads, generic block signature and extended annotation render verbatim with slot provenance', () => {
  const data = boundaries();
  const reference = createReference(data);
  const rows = data.scopes[0].declarations;
  const convert = declarationBody(reference, rows.find((row) => row.name === 'convert'));
  assert.equal((convert.match(/class="api-lens-signature"/g) || []).length, 2);
  assert.match(convert, /\(::String value\) -&gt; ::String/);
  assert.match(convert, /\(::Integer value\) -&gt; ::Integer/);
  const transform = declarationBody(reference, rows.find((row) => row.name === 'transform'));
  assert.match(transform, /%a\{rigor:v1:return: non-empty-string\} \[T\] \(T value\) \{ \(T\) -&gt; ::String \} -&gt; ::String/);
  assert.match(transform, /Block \(required\)<\/dt><dd><code>\(T\) -&gt; ::String<\/code> — sig · <code>sig\/boundaries.rbs<\/code>/);
  assert.match(transform, /Parameter <code>value<\/code> \(required\)<\/dt><dd><code>T<\/code> — sig/);
  assert.match(transform, /Returns<\/dt><dd><code>::String<\/code> — sig/);
});

test('reserved extrbs stays source text while rendered facts retain the released inferred dynamic origin', () => {
  const data = boundaries();
  const row = data.scopes[0].declarations.find((row) => row.name === 'reserved');
  assert.equal(row.contracts[0].channel, 'extrbs');
  assert.equal(row.contracts[0].raw, '# @extrbs (String value) -> Integer');
  assert.equal(row.contracts[0].payload, '(String value) -> Integer');
  const body = declarationBody(createReference(data), row);
  assert.match(body, /untyped<\/code> \(dynamic; inferred return is untyped\) — inferred/);
  assert.doesNotMatch(body, /(?:-&gt;|<code>)\s*(?:::)?Integer| — extrbs/);
});
