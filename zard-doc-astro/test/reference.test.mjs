import assert from 'node:assert/strict';
import test from 'node:test';
import { parseExport } from '../src/model.mjs';
import { createReference } from '../src/index.mjs';
import { starlightPages, starlightTopic } from '../src/starlight.mjs';

import { renderReference } from '../src/render.mjs';
import { prose } from '../src/prose.mjs';
import { namespaceTree, routePages } from '../src/routes.mjs';

const renderPages = (model) => starlightPages(renderReference(model, { basePath: 'apiref' }));

function fixture() {
  const row = (name, anchor, kind = 'instance_method') => ({ id: `app:${anchor}`, name, kind, display_name: `Example#${name}`,
    visibility: 'public', parameters: ['input'], page: 'app/Example.md', anchor,
    span: { path: 'lib/example.rb', start_line: 2 }, documentation: [] });
  const declarations = [row('call', 'zard-01'), row('call', 'zard-02'), row('VALUE', 'zard-03', 'constant')];
  return { schema: 'zard-doc/v0', revision: 1, layout: 'namespace', producer: { zard: '0.0.1', zard_doc: '0.0.1' },
    scopes: [{ name: 'app', destination: 'app', declarations, pages: [{ path: 'app/Example.md', declarations: declarations.map((row) => row.id) }] }], links: {} };
}

test('public interface is reusable without Rigor, Starlight, CSS or filesystem writes', () => {
  const data = fixture();
  const before = structuredClone(data);
  const reference = createReference(data, { basePath: 'docs/sdk', title: 'Example SDK',
    introduction: 'Choose an API.', provenance: [{ label: 'Example source', url: 'https://example.com/source' }] });
  assert.deepEqual(data, before);
  assert.equal(reference.url, '/docs/sdk/');
  const page = reference.pages.find((page) => page.slug === 'docs/sdk/app/example');
  assert.match(page.body, /id="zard-01"/);
  assert.match(page.body, /Example source/);
  assert.doesNotMatch(page.body, /Rigor|<style|style=|--sl-|^---/);
  assert.match(reference.pages[1].body, /\/docs\/sdk\/app\/example\/#zard-02/);
  const topic = starlightTopic(reference, { id: 'sdk', label: { en: 'SDK' } });
  assert.equal(topic.link, reference.url);
  assert.equal(topic.items[1].items[1].link, '/docs/sdk/app/example/');
  const markdown = starlightPages(reference).get('docs/sdk/app/example.md');
  assert.match(markdown, /^---\ntitle: "Example"/);
  assert.match(markdown, /editUrl: false/);
  assert.equal(createReference(data).url, '/api/');
  assert.throws(() => createReference(data, { basePath: '../outside' }), /Invalid API basePath/);
  assert.throws(() => createReference(data, { provenance: [{ label: 'unsafe', url: 'javascript:alert(1)' }] }), /Invalid provenance URL/);
});

test('preserves repeated definitions and supplies real source anchors on rendered pages', () => {
  const model = parseExport(fixture());
  const pages = renderPages(model);
  const page = pages.get('apiref/app/example.md');
  assert.match(page, /id="zard-01"/);
  assert.match(page, /id="zard-02"/);
  assert.match(page, /lib\/example.rb:2/);
  assert.match(page, /## Constants/);
  assert.match(page, /## Instance methods/);
  assert.match(pages.get('apiref/app/index.md'), /\/apiref\/app\/example\/#zard-02/);
  assert.deepEqual(namespaceTree(model.scopes[0], 'apiref'), [{ label: 'Example', url: '/apiref/app/example/', children: [] }]);
});

test('rejects incompatible schemas, private members, escaping paths and missing targets', () => {
  const changes = [
    (data) => { data.revision = 2; },
    (data) => { data.scopes[0].declarations[0].visibility = 'private'; },
    (data) => { data.scopes[0].pages[0].path = '../outside.md'; },
    (data) => { data.scopes[0].declarations[0].span.path = '/Users/private.rb'; },
    (data) => { data.links['app/Example.md'] = [{ path: 'app/Missing.md', anchor: 'zard-01' }]; },
    (data) => { data.scopes[0].pages[0].declarations.pop(); },
  ];
  for (const change of changes) {
    const data = fixture();
    change(data);
    assert.throws(() => parseExport(data), /Invalid ZARD API export/);
  }
});

test('rejects route collisions introduced by slug normalization', () => {
  const data = fixture();
  const other = structuredClone(data.scopes[0]);
  other.name = 'other'; other.destination = 'APP';
  other.declarations.forEach((row) => { row.id = `other:${row.anchor}`; row.page = 'APP/example.md'; });
  other.pages = [{ path: 'APP/example.md', declarations: other.declarations.map((row) => row.id) }];
  data.scopes.push(other);
  assert.throws(() => routePages(parseExport(data), 'apiref'), /route collision/);
});

test('rewrites known API links without changing code or exposing unsafe HTML', () => {
  const model = parseExport(fixture());
  const result = prose('[Call](Example.md#zard-01) `<script>x</script>`\n\n<script>alert(1)</script>\n\n[unsafe](javascript:alert%281%29)\n\n[missing](Missing.md)', 'app/Example.md', model, 'apiref');
  assert.match(result, /\/apiref\/app\/example\/#zard-01/);
  assert.match(result, /`<script>x<\/script>`/);
  assert.doesNotMatch(result, /^<script>/m);
  assert.doesNotMatch(result, /javascript:/);
  assert.doesNotMatch(result, /\]\(Missing.md\)/);
});

test('escaped identifiers cannot become generated markup', () => {
  const data = fixture();
  data.scopes[0].declarations[0].display_name = '<img src=x onerror=alert(1)>';
  const page = renderPages(parseExport(data)).get('apiref/app/example.md');
  assert.doesNotMatch(page, /<img /);
  assert.match(page, /&lt;img/);
});

test('combines consecutive prose lines before Markdown parsing and preserves paragraph gaps', () => {
  const data = fixture();
  data.scopes[0].declarations[0].documentation = [
    ['First line', 2], ['continues here.', 3], ['Second paragraph.', 5], ['    first_code_line', 7], ['    second_code_line', 8],
  ].map(([description, line]) => ({ name: 'text', subject: null, rendered_description: description, span: { path: 'lib/example.rb', start_line: line, end_line: line } }));
  const page = renderPages(parseExport(data)).get('apiref/app/example.md');
  assert.match(page, /First line\ncontinues here\.\n\nSecond paragraph\./);
  assert.match(page, /```\nfirst_code_line\nsecond_code_line\n```/);
});

test('preserves conventional two-space Ruby comment examples as one literal code block', () => {
  const result = prose('Example:\n\n  class Example < Base\n    call("example")\n\n    def run\n      nil\n    end\n  end\n\nProse resumes.', 'app/Example.md', parseExport(fixture()));
  assert.match(result, /```\nclass Example < Base\n  call\("example"\)/);
  assert.match(result, /\n  def run\n    nil\n  end\nend\n/);
  assert.equal((result.match(/^```$/gm) || []).length, 2);
  assert.match(result, /Prose resumes\./);
});
