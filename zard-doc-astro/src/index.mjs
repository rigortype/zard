import { parseExport } from './model.mjs';
import { renderReference } from './render.mjs';

// Pure generation: publication and source acquisition belong to the consumer.
export function createReference(data, options = {}) {
  return renderReference(parseExport(data), options);
}
