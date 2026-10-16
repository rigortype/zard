# Rigor lens revision-1 fixture

`expected-0.4.4.json` is unedited output from the released Rigor 0.4.4 CLI, with Prism 1.9.0, RBS 4.2.0 and rbs-inline 0.14.0, run against this same source project using `rigor lens --format=json --workers 0 -- ./lib/order.rb ./lib/shop.rb ./lib/util.rb`. The original expected output remains the compatibility fixture for 0.4.3. Types are never authored in ZARD.

Copied from rigortype/rigor at `634087145b975173434bb207d95bac6b6c1da4d0`, `spec/integration/fixtures/lens/`, under MPL-2.0. The source contracts and expected types are Rigor's shared producer/consumer fixture, not signatures authored by ZARD. The fixed producer was executed against this project and its normalized output matched expected.json. Tests restore the release version and select the requested successful targets; definition/type data is retained verbatim.

Source: https://github.com/rigortype/rigor/tree/634087145b975173434bb207d95bac6b6c1da4d0/spec/integration/fixtures/lens
