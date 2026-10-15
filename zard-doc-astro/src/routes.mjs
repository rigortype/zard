import { slug } from 'github-slugger';

const siteSlugRoute = (route) => route.split('/').map((segment) => slug(segment)).join('/');

export function pageSlug(path, basePath) {
  return `${basePath}/${siteSlugRoute(path.replace(/\.md$/, ''))}`;
}
export const pageUrl = (path, basePath) => `/${pageSlug(path, basePath)}/`;
export const scopeSlug = (scope, basePath) => `${basePath}/${siteSlugRoute(scope.destination)}`;
export const scopeUrl = (scope, basePath) => `/${scopeSlug(scope, basePath)}/`;
export const hasRelationships = (scope) => scope.declarations.some((row) => row.relationships != null);
export const hierarchySlug = (scope, basePath) => `${scopeSlug(scope, basePath)}/hierarchy`;

export function routePages(model, basePath) {
  const routes = new Map([[basePath, 'API landing']]);
  const add = (slug, owner) => {
    if (routes.has(slug) || slug.split('/').some((part) => !part || part === '.' || part === '..')) {
      throw new Error(`API route collision or empty slug: ${slug} (${owner})`);
    }
    routes.set(slug, owner);
  };
  for (const scope of model.scopes) {
    add(scopeSlug(scope, basePath), scope.name);
    if (hasRelationships(scope)) add(hierarchySlug(scope, basePath), `${scope.name} hierarchy`);
    for (const page of scope.pages) add(pageSlug(page.path, basePath), page.path);
  }
  return routes;
}

export function namespaceTree(scope, basePath) {
  const root = { children: new Map() };
  for (const page of scope.pages) {
    const segments = page.path.slice(scope.destination.length + 1).replace(/\.md$/, '').split('/');
    let node = root;
    for (const segment of segments) {
      if (!node.children.has(segment)) node.children.set(segment, { label: segment, children: new Map() });
      node = node.children.get(segment);
    }
    node.page = page;
  }
  const items = (node) => [...node.children.values()].sort((a, b) => a.label.localeCompare(b.label, 'en')).map((child) => {
    const descendants = items(child);
    return { label: child.label, url: child.page ? pageUrl(child.page.path, basePath) : null, children: descendants };
  });
  return items(root);
}
