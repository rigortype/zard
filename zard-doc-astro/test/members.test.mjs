import assert from 'node:assert/strict';
import test from 'node:test';
import { compareMembers } from '../src/members.mjs';

test('member order retains repeated definitions with locale-independent source tie breakers', () => {
  const rows = [
    {name:'zebra',path:'a.rb',line:2,anchor:'zard-02'},
    {name:'alpha',path:'b.rb',line:1,anchor:'zard-03'},
    {name:'alpha',path:'a.rb',line:4,anchor:'zard-04'},
    {name:'alpha',path:'a.rb',line:4,anchor:'zard-01'},
  ];
  assert.deepEqual(rows.toSorted(compareMembers).map((row) => row.anchor), ['zard-02','zard-01','zard-04','zard-03']);
  assert.deepEqual(rows.toSorted((a,b) => compareMembers(a,b,'name')).map((row) => row.anchor), ['zard-01','zard-04','zard-03','zard-02']);
  assert.equal(compareMembers(rows[0],rows[0]),0);
});
