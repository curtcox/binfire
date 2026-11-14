// App URL state classification (spec/state.md).
import { utf8Length } from './bytes';
import { isCid } from './cid';
import { parseQuery, queryGet, queryHas, rawFragment, rawQuery } from './url';

export type StateKind =
  | 'publish'
  | 'cid'
  | 'v1'
  | 'unsupported-version'
  | 'src'
  | 'h1'
  | 'fragment'
  | 'doc'
  | 'compressed'
  | 'example'
  | 'none';

export interface StateInfo {
  state: StateKind;
  /** `false` only when the query has `run=0`. */
  run: boolean;
  /** The `view` query value, or `null`. */
  view: string | null;
  /** The CID, when `state` is `cid`. */
  cid?: string;
  /** UTF-8 length of the whole URL string. */
  bytes: number;
}

/**
 * Classifies the state carried by an app URL (FK `createUrlState().parse`
 * precedence). The fragment is used raw; the query is decoded like
 * `URLSearchParams`. Never rewrites the URL.
 */
export function classifyState(url: string): StateInfo {
  const hash = rawFragment(url) ?? '';
  const params = parseQuery(rawQuery(url));
  const run = queryGet(params, 'run') !== '0';
  const view = queryGet(params, 'view');
  const bytes = utf8Length(url);
  const result = (state: StateKind): StateInfo => ({ state, run, view, bytes });

  if (queryHas(parseQuery(hash), 'hashbin_publish')) return result('publish');
  if (isCid(hash)) return { ...result('cid'), cid: hash };
  if (hash.startsWith('v1.')) return result('v1');
  if (/^v[0-9]+\./.test(hash)) return result('unsupported-version');
  if (hash.startsWith('src=')) return result('src');
  if (hash.startsWith('h1=')) return result('h1');
  if (hash) return result('fragment');
  if (queryHas(params, 'doc')) return result('doc');
  if (queryHas(params, 'compressed')) return result('compressed');
  if (queryHas(params, 'example')) return result('example');
  return result('none');
}
