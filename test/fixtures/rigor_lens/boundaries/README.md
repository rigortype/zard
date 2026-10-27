# Released lens boundary fixture

The Ruby and RBS files are authored test inputs for explicit singleton receivers,
two refinement groups with same-named methods, reserved `@extrbs` text, overloads,
and a generic block signature carrying an extended annotation.

`expected.json` is unedited output from released Rigor 0.4.5, with Prism 1.9.0,
RBS 4.2.0 and rbs-inline 0.14.0, run in a temporary copy of this directory:

```sh
rigor lens --format=json --workers 0 -- ./lib/boundaries.rb
```

The companion `zard-doc-astro/test/fixtures/lens-boundaries-export.json` is the
actual enriched ZARD CLI export of that project, using a single `app` scope,
`destination: app`, `sources: [{root: lib}]` and namespace layout. It contains
producer facts, not manually authored expected type results.

`RigorLensBoundariesTest` verifies source provenance and bindings against the raw
fixture. With `ZARD_RIGOR_COMMAND` set, it runs the released executable again and
compares the complete enriched result to both fixture-based enrichment and the
Astro fixture. The Astro tests render that same output through `createReference`.

Rigor 0.4.5 reports the non-self receiver and refinement blocks as omissions.
Their ZARD definitions remain distinct unavailable bindings. It does not
interpret reserved `@extrbs` contracts: the raw contract stays in the ZARD export,
while the member retains its independently inferred dynamic type. The authored
RBS extended annotation, overloads, type parameter and required block are
preserved verbatim in the producer signature display text.
