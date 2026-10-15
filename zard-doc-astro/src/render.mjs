import { code, escapeHtml, markdownText, prose } from './prose.mjs';
import { renderLens, renderLensSummary } from './lens.mjs';
import { pageSlug, pageUrl, routePages, scopeSlug, scopeUrl, namespaceTree } from './routes.mjs';

const link = (label, href, index = false) => `<a${index ? ' class="api-index-link"' : ''} href="${escapeHtml(href)}">${escapeHtml(label)}</a>`;
const crumbs = (items) => `<nav class="api-breadcrumbs" aria-label="Breadcrumb"><ol>${items.map(([label, href]) => `<li>${href ? link(label, href) : `<span aria-current="page">${escapeHtml(label)}</span>`}</li>`).join('')}</ol></nav>\n\n`;
const declarationKind = (kind) => {
  if (kind === 'class' || kind === 'module' || kind === 'constant' || kind === 'refinement') return kind;
  if (kind.includes('attribute')) return 'attribute';
  return kind.startsWith('singleton_') ? 'singleton method' : 'instance method';
};
const titleFor = (scope, page) => page.path.slice(scope.destination.length + 1).replace(/\.md$/, '').split('/').join('::');
const categories = [['Classes', 'class'], ['Modules', 'module'], ['Constants', 'constant'], ['Attributes', 'attribute'], ['Instance methods', 'instance method'], ['Singleton methods', 'singleton method'], ['Ruby refinements', 'refinement']];

function memberIndex(rows, basePath) {
  const groups = categories.filter(([, kind]) => ['attribute', 'instance method', 'singleton method'].includes(kind));
  const content = groups.map(([title, kind]) => {
    const members = rows.filter((row) => declarationKind(row.kind) === kind);
    if (!members.length) return '';
    const items = members.map((row) => {
      const parameters = row.parameterDetails?.map((parameter) => parameter.source) ?? row.parameters;
      const signature = kind.includes('method') ? `${row.displayName}(${parameters.join(', ')})` : row.displayName;
      return `<li><a class="api-index-link" href="${escapeHtml(`${pageUrl(row.page, basePath)}#${row.anchor}`)}">${code(signature)}</a><span class="api-meta">${escapeHtml(`${row.source.path}:${row.source.line}`)}</span></li>`;
    });
    return `<details open><summary>${title} (${members.length})</summary><ul>${items.join('\n')}</ul></details>`;
  }).join('\n');
  return content.trim() ? `## Member index\n\n<nav class="api-member-index" aria-label="Members on this page">${content}</nav>\n\n` : '';
}

function indexEntries(rows, basePath) {
  return categories.map(([title, kind]) => {
    const matches = rows.filter((row) => declarationKind(row.kind) === kind);
    if (!matches.length) return '';
    return `## ${title}\n\n${matches.map((row) => `- ${link(row.displayName, `${pageUrl(row.page, basePath)}#${row.anchor}`, true)}`).join('\n')}\n\n`;
  }).join('');
}

function entry(row, model, basePath, sourceLinks) {
  const kind = declarationKind(row.kind);
  const parameters = row.parameterDetails?.map((parameter) => parameter.source) ?? row.parameters;
  const signature = kind.includes('method') ? `${row.displayName}(${parameters.join(', ')})` : row.displayName;
  const location = `${row.source.path}:${row.source.line}`;
  const source = Object.hasOwn(sourceLinks, row.id) ? link(location, sourceLinks[row.id]) : code(location);
  let result = `<section class="api-declaration" aria-labelledby="${row.anchor}">\n\n<h3 id="${row.anchor}" class="api-signature">${code(signature)}</h3>\n\n<p class="api-meta">${escapeHtml(kind)} · ${source}</p>\n\n`;
  const texts = row.tags.filter((tag) => tag.name === 'text');
  const description = texts.map((tag, i) => {
    const previous = texts[i - 1];
    const gap = previous ? '\n'.repeat(tag.line > previous.endLine + 1 ? 2 : 1) : '';
    return gap + tag.description;
  }).join('');
  result += renderLens(row, model.lens);
  result += prose(description, row.page, model, basePath);
  for (const tag of row.tags.filter((tag) => !['text', 'raw'].includes(tag.name))) {
    const names = { param: 'Parameter', return: 'Returns', yieldparam: 'Block parameter', yieldreturn: 'Block returns', raise: 'Raises', note: 'Note', see: 'See also', deprecated: 'Deprecated', example: 'Example', option: 'Option' };
    result += `\n**${names[tag.name] || markdownText(tag.name)}${tag.subject ? ` ${code(tag.subject)}` : ''}**\n\n`;
    result += tag.name === 'example'
      ? `<pre class="api-example"><code>${escapeHtml(tag.description)}</code></pre>\n`
      : prose(tag.description, row.page, model, basePath);
  }
  return `${result}\n</section>\n\n`;
}

export function renderReference(model, options = {}) {
  const { basePath = 'api', title = 'API Reference', description = 'Public API declarations.',
    introduction = '', provenance = [], sourceLinks = {} } = options;
  if (!/^[a-z0-9_-]+(?:\/[a-z0-9_-]+)*$/.test(basePath)) throw new Error('Invalid API basePath');
  routePages(model, basePath);
  const ids = new Set(model.scopes.flatMap((scope) => scope.declarations.map((row) => row.id)));
  for (const [id, url] of Object.entries(sourceLinks)) {
    if (!ids.has(id) || typeof url !== 'string' || !/^https?:\/\//i.test(url)) throw new Error('Invalid declaration source link');
    const target = new URL(url);
    if (target.username || target.password) throw new Error('Invalid declaration source link credentials');
  }
  const pages = [];
  const add = (slug, title, description, body) => pages.push({ slug, title, description, body });
  const provenanceHtml = (model.lens ? `<p class="api-lens-status">Rigor ${escapeHtml(model.lens.producer.version)} · experimental ${escapeHtml(model.lens.schema)} revision ${model.lens.revision}. Body returns use declared or unknown parameter types.</p>\n\n` : '') + (provenance.length
    ? `<p class="api-provenance">${provenance.map(({ label, url }) => {
      if (url && !/^https?:\/\//i.test(url)) throw new Error('Invalid provenance URL');
      return url ? link(label, url) : escapeHtml(label);
    }).join(' · ')}</p>\n\n` : '');
  let root = provenanceHtml + (introduction ? prose(introduction, '', model, basePath) + '\n' : '');
  root += model.scopes.length ? model.scopes.map((scope) => `- ${link(scope.name, scopeUrl(scope, basePath), true)} — ${scope.pages.length} namespace pages, ${scope.declarations.length} public declarations`).join('\n') : 'No public declarations were exported. Check the selected source mappings before publishing.';
  add(basePath, title, description, root + '\n');
  for (const scope of model.scopes) {
    let index = crumbs([[title, `/${basePath}/`], [scope.name]]) + provenanceHtml;
    index += indexEntries(scope.declarations, basePath) || 'No public declarations were exported for this documentation scope.\n';
    add(scopeSlug(scope, basePath), `${scope.name} API`, `Public API declarations in the ${scope.name} documentation scope.`, index);
    for (const page of scope.pages) {
      const pageTitle = titleFor(scope, page);
      const segments = pageTitle.split('::');
      const ancestors = segments.slice(0, -1).flatMap((_, i) => {
        const candidate = `${scope.destination}/${segments.slice(0, i + 1).join('/')}.md`;
        return scope.pages.some((item) => item.path === candidate) ? [[segments[i], pageUrl(candidate, basePath)]] : [];
      });
      let content = crumbs([[title, `/${basePath}/`], [scope.name, scopeUrl(scope, basePath)], ...ancestors, [segments.at(-1)]]) + provenanceHtml;
      content += renderLensSummary(page.declarations, model.lens);
      content += memberIndex(page.declarations, basePath);
      for (const [category, kind] of categories) {
        const rows = page.declarations.filter((row) => declarationKind(row.kind) === kind);
        if (rows.length) content += `## ${category}\n\n${rows.map((row) => entry(row, model, basePath, sourceLinks)).join('')}`;
      }
      add(pageSlug(page.path, basePath), pageTitle, `Public declarations and source documentation for ${pageTitle}.`, content);
    }
  }
  return { title, url: `/${basePath}/`, pages, navigation: model.scopes.map((scope) => ({
    label: scope.name, indexUrl: scopeUrl(scope, basePath), items: namespaceTree(scope, basePath),
  })) };
}
