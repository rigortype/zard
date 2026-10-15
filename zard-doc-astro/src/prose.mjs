import path from 'node:path';
import { fromMarkdown } from 'mdast-util-from-markdown';
import { toMarkdown } from 'mdast-util-to-markdown';
import { pageUrl } from './routes.mjs';

export const escapeHtml = (text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
export const code = (text) => `<code>${escapeHtml(text).replaceAll('\r', '&#13;').replaceAll('\n', '&#10;')}</code>`;
export const markdownText = (value) => toMarkdown({ type: 'root', children: [{ type: 'paragraph', children: [{ type: 'text', value }] }] }).trim();

function commentCodeBlocks(markdown) {
  const lines = markdown.split('\n');
  const result = [];
  let fence = null;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (marker) {
      if (!fence) fence = marker[1];
      else if (marker[1][0] === fence[0] && marker[1].length >= fence.length) fence = null;
    }
    const previous = lines.slice(0, i).findLast((item) => item.trim());
    const afterList = previous && /^\s*(?:[-*+]|\d+[.)])\s/.test(previous);
    if (!fence && !afterList && (i === 0 || !lines[i - 1].trim()) && /^ {2,3}\S/.test(line) && !/^\s*(?:[-*+]|\d+[.)])\s/.test(line)) {
      const block = [];
      while (i < lines.length && (!lines[i].trim() || /^ {2}/.test(lines[i]))) block.push(lines[i++].replace(/^ {2}/, ''));
      i--;
      const delimiter = '`'.repeat(Math.max(3, ...block.flatMap((item) => [...item.matchAll(/`+/g)].map((match) => match[0].length + 1))));
      result.push(delimiter, ...block, delimiter, '');
    } else result.push(line);
  }
  return result.join('\n');
}

export function prose(markdown, from, model, basePath = 'api') {
  const pages = new Map(model.scopes.flatMap((scope) => scope.pages.map((page) => [page.path, page])));
  const tree = fromMarkdown(commentCodeBlocks(markdown));
  const rewrite = (node) => {
    if (node.type === 'html') return { type: 'text', value: node.value };
    if (node.type === 'image' || node.type === 'imageReference') return { type: 'text', value: node.alt || 'Image' };
    if (node.type === 'heading') node.depth = Math.min(6, Math.max(3, node.depth + 2));
    if (node.children) node.children = node.children.flatMap((child) => {
      const result = rewrite(child);
      return Array.isArray(result) ? result : [result];
    });
    if (node.type === 'definition' || node.type === 'link') {
      const original = node.url;
      if (/^(?:https?:|mailto:)/i.test(original)) return node;
      let target;
      try {
        const url = new URL(original, `https://api.invalid/${from}`);
        if (url.origin === 'https://api.invalid') {
          const candidate = decodeURIComponent(url.pathname.slice(1));
          const page = pages.get(path.posix.normalize(candidate));
          if (page && !url.search && (!url.hash || page.declarations.some((row) => `#${row.anchor}` === url.hash))) {
            target = `${pageUrl(page.path, basePath)}${url.hash}`;
          }
        }
      } catch { /* An invalid URL remains readable text. */ }
      if (target) { node.url = target; return node; }
      return node.type === 'link' ? node.children : { type: 'text', value: `[${node.label || node.identifier}]` };
    }
    return node;
  };
  tree.children = tree.children.flatMap((node) => {
    const rewritten = rewrite(node);
    return Array.isArray(rewritten) ? rewritten : [rewritten];
  });
  return toMarkdown(tree);
}
