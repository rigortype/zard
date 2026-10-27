# Released lens type-reference fixture

The Ruby and RBS files are authored inputs for signature type links across six
documentation scopes (`zard-doc.yml`):

- `app` references `shared`, `left` and `right`; `shared` references `app`
  (a cycle) and `far`, so `far` is transitive from `app`.
- `left` and `right` both document `Twin`, so `app` sees competing candidates.
- `unrelated` documents `Lonely` and another `App::Foo` but is referenced by no scope.
- `App::Common` is documented by both `app` and `shared`; `App::Foo` is reopened
  in two `app` files; `App::Hidden` is `@api internal`; `App::Point` comes from
  `Data.define`; `App::Box` is generic over `T`; `App::Service#make` has an
  inferred return; `App::Service#convert` is overloaded in `sig/service.rbs`.

`expected.json` is unedited output from released Rigor 0.4.5, with Prism 1.9.0,
RBS 4.2.0 and rbs-inline 0.14.0, run in a temporary copy of this directory under
a UTF-8 locale (Rigor escapes `"ä"` as `"ä"` otherwise):

```sh
rigor lens --format=json --workers 0 -- $(find lib -name '*.rb' | sort | sed 's|^|./|')
```

`zard-doc-astro/test/fixtures/type-references-export.json` and
`type-references-file-export.json` are the actual enriched CLI exports of that
copy in namespace and file layout:

```sh
zard-doc build --config zard-doc.yml --format json --layout namespace \
  --lens-root . --rigor-command rigor --lens-workers 0
```

`RigorTypeReferenceLinksTest` builds the same exports through `zard-doc` with
the raw fixture. With `ZARD_RIGOR_COMMAND` set, it runs the released executable
again and requires both exports to match the Astro fixtures exactly.
