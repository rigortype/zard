import assert from 'node:assert/strict';
import test from 'node:test';
import { createReference } from '../src/index.mjs';

function declaration(name, number, scope = 'app', kind = 'class') {
  const anchor = `zard-${number.toString(16).padStart(2, '0')}`;
  return { id: `${scope}:${anchor}`, kind, name, display_name: name, visibility: 'public', parameters: [],
    page: `${scope}/${name}.md`, anchor, span: {path: `lib/${name.toLowerCase()}.rb`, start_line: number},
    documentation: [], relationships: [] };
}
const target = (row) => ({scope: row.id.split(':')[0], declaration_id:row.id, path:row.page, anchor:row.anchor});
const relation = (row, kind = 'superclass') => ({kind, expression: row.display_name, span: row.span, status:'resolved', targets:[target(row)]});
function document(groups, dependencies = {}) {
  return {schema:'zard-doc/v0', revision:1, layout:'namespace', producer:{zard:'0.0.1',zard_doc:'0.0.1'}, links:{},
    scopes:Object.entries(groups).map(([name, declarations]) => ({name,destination:name,references:dependencies[name] || [], declarations,
      pages:[...new Set(declarations.map((row) => row.page))].map((path) => ({path,declarations:declarations.filter((row) => row.page === path).map((row) => row.id)}))}))};
}

test('source relationships link forwards, backwards and into a separate module usage list', () => {
  const parent = declaration('Parent',1), child = declaration('Child',2), feature = declaration('Feature',3,'app','module');
  child.relationships = [relation(parent), relation(feature,'include'), relation(feature,'prepend'), relation(feature,'extend')];
  const data = document({app:[parent,child,feature]});
  const before = structuredClone(data);
  const result = createReference(data);
  assert.deepEqual(data,before);
  const childPage = result.pages.find((page) => page.slug === 'api/app/child').body;
  assert.match(childPage,/Superclass written in source/);
  assert.match(childPage,/href="\/api\/app\/parent\/#zard-01"/);
  assert.match(result.pages.find((page) => page.slug === 'api/app/parent').body,/Known documented subclass/);
  const tree = result.pages.find((page) => page.slug === 'api/app/hierarchy').body;
  assert.match(tree, /parent\/#zard-01[\s\S]*?<ul><li>[\s\S]*?child\/#zard-02/);
  assert.match(tree,/## Module usage/);
  assert.match(tree,/prepend:/);
  assert.match(tree,/do not establish effective runtime ancestry/);
  assert.equal(result.navigation[0].items[0].url,'/api/app/hierarchy/');
});

test('cycles and conflicting reopened superclasses remain finite and produce diagnostics', () => {
  const a = declaration('A',1), b = declaration('B',2), child = declaration('Child',3), reopening = declaration('Child',4);
  a.relationships = [relation(b)]; b.relationships = [relation(a)];
  child.relationships = [relation(a)]; reopening.relationships = [relation(b)];
  const result = createReference(document({app:[a,b,child,reopening]}));
  assert.equal(result.diagnostics.length,2);
  assert.ok(result.diagnostics.some((value) => value.includes('Cycle')));
  assert.ok(result.diagnostics.some((value) => value.includes('Conflicting written superclass')));
  const tree = result.pages.find((page) => page.slug.endsWith('/hierarchy')).body;
  assert.match(tree,/cycle; hierarchy not expanded/);
  assert.match(tree,/unresolved or conflicting superclass references/);
  assert.match(tree,/#zard-03/); assert.match(tree,/#zard-04/);
  assert.ok(tree.length < 5000);
});

test('only direct dependency targets are admitted and dynamic expressions stay literal', () => {
  const parent = declaration('Parent',1,'dep'), child = declaration('Child',2);
  child.relationships = [relation(parent)];
  const data = document({app:[child],dep:[parent]}, {app:['dep']});
  assert.match(createReference(data).pages.find((page) => page.slug === 'api/app/hierarchy').body,/superclass in dep/);
  data.scopes[0].references = [];
  assert.throws(() => createReference(data),/outside direct documentation dependencies/);
  data.scopes[0].references = ['dep'];
  child.relationships[0].targets[0].declaration_id = 'missing';
  assert.throws(() => createReference(data),/missing relationship target/);
  child.relationships = [{kind:'superclass', expression:'factory("<x>")',span:child.span,status:'expression',targets:[]}];
  const result = createReference(data);
  assert.match(result.pages.find((page) => page.slug === 'api/app/child').body,/source expression; no parent inferred/);
  assert.match(result.pages.find((page) => page.slug === 'api/app/child').body,/&lt;x&gt;/);
});

test('hierarchy routes cannot collide with normalized declaration routes', () => {
  assert.throws(() => createReference(document({app:[declaration('Hierarchy',1)]})),/route collision/);
});

test('deep class chains render without recursive graph traversal', () => {
  const rows = Array.from({length:600}, (_, index) => declaration(`Class${index}`, index + 1));
  rows.forEach((row,index) => { if (index) row.relationships = [relation(rows[index-1])]; });
  const result = createReference(document({app:rows}));
  const tree = result.pages.find((page) => page.slug.endsWith('/hierarchy')).body.split('## Class hierarchy')[1].split('## Module usage')[0];
  assert.equal((tree.match(/<li>/g) || []).length,600);
  assert.equal((tree.match(/<ul/g) || []).length,(tree.match(/<\/ul>/g) || []).length);
  assert.deepEqual(result.diagnostics,[]);
});
