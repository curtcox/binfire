// HashBin document envelopes (spec/state.md, "Envelopes").
import { utf8Decode } from './bytes';

/**
 * Classifies a HashBin document's bytes: `"<format>:<type>"`, `"<format>"`,
 * `"source"` for a JSON string, or `null`. A leading BOM is ignored, as
 * TextDecoder does.
 */
export function documentType(bytes: Uint8Array): string | null {
  const text = utf8Decode(bytes);
  if (text === null) return null;
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof value === 'string') return 'source';
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const { format, type } = value as { format?: unknown; type?: unknown };
  if (typeof format !== 'string') return null;
  return typeof type === 'string' ? `${format}:${type}` : format;
}

export { appsForDocumentType } from './registry';
