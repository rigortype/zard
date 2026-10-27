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
