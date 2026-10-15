// Starlight's content and sidebar conventions stay out of the generic renderer.
export function starlightPages(reference) {
  const indexes = new Set([reference.url, ...reference.navigation.map((scope) => scope.indexUrl)].map((url) => url.slice(1, -1)));
  return new Map(reference.pages.map(({ slug, title, description, body }) => [
    `${slug}${indexes.has(slug) ? '/index' : ''}.md`,
    `---\ntitle: ${JSON.stringify(title)}\ndescription: ${JSON.stringify(description)}\neditUrl: false\nprev: false\nnext: false\n---\n\n${body}`,
  ]));
}

export function starlightTopic(reference, { id, label = reference.title, overviewLabel = reference.title } = {}) {
  const items = (nodes) => nodes.map((node) => node.children.length
    ? { label: node.label, collapsed: true, items: [
      ...(node.url ? [{ label: `${node.label} overview`, link: node.url }] : []), ...items(node.children),
    ] }
    : { label: node.label, link: node.url });
  return { id, label, link: reference.url, icon: 'document', items: [
    { label: overviewLabel, link: reference.url },
    ...reference.navigation.map((scope) => ({ label: scope.label, collapsed: false, items: [
      { label: `${scope.label} index`, link: scope.indexUrl }, ...items(scope.items),
    ] })),
  ] };
}
