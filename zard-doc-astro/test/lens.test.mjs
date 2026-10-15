import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { createReference } from '../src/index.mjs';

// Real zard-doc + Rigor 0.4.3 output over Rigor's pinned shared fixture.
const fixture = () => JSON.parse(readFileSync(new URL('fixtures/lens-export.json', import.meta.url), 'utf8'));

test('shows member facts, site body returns and unavailable/dynamic states without parsing types', () => {
  const data = fixture();
  const reference = createReference(data);
  const body = reference.pages.find((page) => page.slug === 'api/app/shop').body;
  assert.match(body, /Shared across its definitions/);
  assert.match(body, /Signature unavailable: multiple definitions/);
  assert.match(body, /Unavailable — multiple definitions/);
  assert.match(body, /Body return for this definition/);
  assert.match(body, /Rigor type information unavailable: .*not supported/);
  assert.match(body, /Type information coverage/);
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

test('rejects incompatible lens data and dangling joins instead of publishing guessed types', () => {
  const mutations = [
    (data) => { data.lens.revision = 2; },
    (data) => { data.lens.producer.version = '0.4.2'; },
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
