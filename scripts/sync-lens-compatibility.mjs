import { readFile, writeFile } from 'node:fs/promises';

const source = new URL('../zard-rigor/lib/zard/rigor/compatibility.json', import.meta.url);
const target = new URL('../zard-doc-astro/src/lens-compatibility.json', import.meta.url);
const expected = await readFile(source, 'utf8');
const manifest = JSON.parse(expected);
if (!manifest.versions.includes(manifest.default_version)) throw new Error('Default Rigor version must be explicitly supported');
if (process.argv.includes('--check')) {
  if (await readFile(target, 'utf8') !== expected) throw new Error('Run node scripts/sync-lens-compatibility.mjs before testing/packing');
} else {
  await writeFile(target, expected);
}
