# zard-doc-astro

An experimental, unstyled presentation package for Astro content sites consuming ZARD's `zard-doc/v0`, revision 1 JSON export. It is developed alongside the Ruby producer but has no Ruby or Rigor runtime dependency. It is not published to npm yet.

## Responsibilities

| Owner | Responsibility |
| --- | --- |
| `zard-doc` | Ruby declarations, documentation, contracts, source provenance and resolved references in versioned JSON. |
| `zard-doc-astro` | Export validation, route mapping, safe prose, semantic HTML, declaration anchors, breadcrumbs and namespace navigation. |
| `zard-doc-astro/starlight` | Starlight Markdown frontmatter, index file organization and sidebar-topic configuration. |
| Consumer | CSS, typography, layout, source selection/acquisition, product copy, localization, source URL policy, filesystem publication and deployment. |

The package ships no CSS, inline styles, theme variables or default stylesheet. It does not invoke the producer, read a checkout, write content, choose a repository URL or initialize Astro. Consumers publish the returned pages into their content collection using their existing Astro build. The current adapter targets Starlight's content conventions; other Astro integrations can consume the page records directly.

## Interface

```js
import { createReference } from 'zard-doc-astro';
import { starlightPages, starlightTopic } from 'zard-doc-astro/starlight';

const reference = createReference(exportData, {
  basePath: 'api', // normalized segments, no leading/trailing slash
  title: 'API Reference',
  description: 'Public SDK declarations.',
  introduction: 'Choose an API.', // safe Markdown
  provenance: [{ label: 'SDK source', url: 'https://example.com/source' }],
});
const files = starlightPages(reference); // Map<relative Markdown path, content>
const topic = starlightTopic(reference, { id: 'api', label: 'API Reference' });
```

`createReference` is synchronous and does not mutate the export. It returns `{ title, url, pages, navigation }`; each page contains `{ slug, title, description, body }`, where body is Markdown with semantic HTML. Navigation contains documentation scopes and namespace trees. Unsupported schema/revision, non-public declarations, unsafe logical output paths, unmatched declarations, missing reference targets and normalized route collisions throw before publication. Only namespace layout is supported initially.

Signatures use additive `parameter_details[].source` when supplied by the producer, retaining Ruby defaults, forwarding and anonymous/destructured parameter patterns. Older exports fall back to `parameters`. These are syntax labels, not inferred types. An optional `sourceLinks` object maps declaration IDs to HTTP(S) URLs; the renderer checks IDs and protocols and displays each declaration's own source link. The consumer owns URL templates, commit pinning and repository-path policy. With no link, the recorded source location remains readable text.

`basePath` defaults to `api`. Route segments follow Astro's `github-slugger` normalization. Stable ZARD declaration anchors remain unchanged, including repeated definitions. Provenance labels are escaped and optional links must use HTTP(S). Consumer-supplied localization entry pages can be added after `starlightPages`; locale prefixes and fallback policy are not inferred.

Starlight dependencies are not imported at runtime: the adapter returns the Markdown/configuration values for the consumer's existing installation. Full-text search and content rendering remain the host's responsibility.

## Styling interface

Consumers style these hooks with their own stylesheet:

- `.api-breadcrumbs`: semantic `nav`/`ol` breadcrumb structure.
- `.api-index-link`: links in scope and declaration lists.
- `.api-provenance`: optional source/build attribution.
- `.api-declaration`: a declaration `section` labelled by its heading.
- `.api-signature`: declaration heading containing escaped source parameter labels.
- `.api-meta`: declaration kind and source location.
- `.api-example`: literal example `pre`/`code`.
- `.api-lens`: optional member facts and this definition's body return.
- `.api-lens-signature`: verbatim escaped Rigor signature in `pre`/`code`.
- `.api-lens-status`: experimental protocol notice or unavailable binding.

An optional `lens` extension from `zard-rigor` supports Rigor 0.4.3's experimental
`lens/v0` revision 1. Member signatures are shared across definitions; body
returns belong to one definition. Dynamic and unavailable states retain their
meaning. The renderer neither parses type text nor selects runtime winners.
It rejects incompatible revisions and dangling bindings before publication.

Hooks and structure are an experimental presentation contract. Accessibility attributes and stable IDs belong to the renderer; focus appearance, spacing, wrapping and header scroll offsets belong to consumer CSS. Consumers must provide responsive layout and keyboard-visible focus appropriate to their site. Contracts remain in the export and are not presented as inferred signatures.

## Development and distribution

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm pack --pack-destination /tmp/zard-doc-astro
```

Until registry publication, a consumer can check in the packed archive and install it with a relative `file:` dependency. The archive contains only this package's source, README, license and manifest. This explicit snapshot keeps consumer builds reproducible without relying on a developer's sibling checkout or installing the Ruby repository as an npm package. Refresh the archive from a reviewed package revision when changing the renderer.
