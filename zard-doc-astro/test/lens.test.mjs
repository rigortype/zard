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
  assert.match(body, /Rigor type information unavailable: not reported/);
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
