# Rigor lens revision-1 fixture

`expected.json` is unedited output from the released Rigor 0.4.5 CLI, with Prism 1.9.0, RBS 4.2.0 and rbs-inline 0.14.0, run against this source project using `rigor lens --format=json --workers 0 -- ./lib/order.rb ./lib/shop.rb ./lib/util.rb`. Types are never authored in ZARD. Only the current supported producer is retained.

The source project was copied from rigortype/rigor at `634087145b975173434bb207d95bac6b6c1da4d0`, `spec/integration/fixtures/lens/`, under MPL-2.0. The contracts are Rigor's shared producer/consumer fixture, not signatures authored by ZARD. Expected declaration/type data is regenerated verbatim by the supported released executable.

Source: https://github.com/rigortype/rigor/tree/634087145b975173434bb207d95bac6b6c1da4d0/spec/integration/fixtures/lens
