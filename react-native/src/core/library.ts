// The local library model (spec/ui.md, "Library data"). Pure functions over
// an immutable value; persistence lives in the UI layer.
import { utf8Length } from './bytes';

export const LIBRARY_VERSION = 1;
/** `recent` is capped at this many entries. */
export const MAX_RECENT = 100;
/** `recent` is also capped at this many total URL bytes (UTF-8). */
export const MAX_RECENT_BYTES = 16 * 1024 * 1024;
/** A URL larger than this (UTF-8 bytes) is never added to `recent`. */
export const MAX_RECENT_URL_BYTES = 1024 * 1024;

export interface SavedState {
  id: string;
  name: string;
  url: string;
  app: string;
  /** ISO 8601 timestamp. */
  savedAt: string;
}

export interface RecentState {
  url: string;
  app: string;
  /** ISO 8601 timestamp. */
  visitedAt: string;
}

export interface SavedSite {
  cid: string;
  name: string;
  addedAt: string;
}

export interface Library {
  version: 1;
  /** Newest first, no cap, duplicate URLs allowed. */
  saved: readonly SavedState[];
  /** Newest first, unique by `url`, at most MAX_RECENT entries and MAX_RECENT_BYTES of URLs. */
  recent: readonly RecentState[];
  sites: readonly SavedSite[];
}

export const emptyLibrary: Library = {
  version: LIBRARY_VERSION,
  saved: [],
  recent: [],
  sites: [],
};

/** Keeps the newest entries within MAX_RECENT and MAX_RECENT_BYTES, dropping the oldest. */
function capRecent(list: readonly RecentState[]): RecentState[] {
  const out: RecentState[] = [];
  let bytes = 0;
  for (const r of list) {
    if (out.length >= MAX_RECENT) break;
    bytes += utf8Length(r.url);
    if (bytes > MAX_RECENT_BYTES) break;
    out.push(r);
  }
  return out;
}

/**
 * Records a visit: moves or inserts `url` at the front, then caps the list.
 * URLs over MAX_RECENT_URL_BYTES are not recorded (save them by name instead).
 */
export function addRecent(lib: Library, url: string, app: string, now: Date = new Date()): Library {
  if (url.length > MAX_RECENT_URL_BYTES || utf8Length(url) > MAX_RECENT_URL_BYTES) return lib;
  const entry: RecentState = { url, app, visitedAt: now.toISOString() };
  return {
    ...lib,
    recent: capRecent([entry, ...lib.recent.filter(r => r.url !== url)]),
  };
}

/** Adds a named save at the front. */
export function addSaved(
  lib: Library,
  save: { id: string; name: string; url: string; app: string },
  now: Date = new Date(),
): Library {
  return {
    ...lib,
    saved: [{ ...save, savedAt: now.toISOString() }, ...lib.saved],
  };
}

/** Removes the saved state with this id. */
export function removeSaved(lib: Library, id: string): Library {
  return { ...lib, saved: lib.saved.filter(s => s.id !== id) };
}

const isStr = (v: unknown): v is string => typeof v === 'string';
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

/**
 * Reads a persisted library. Malformed entries are dropped and a missing or
 * unreadable file gives an empty library, so a bad file never blocks start-up.
 */
export function parseLibrary(text: string | null | undefined): Library {
  if (!text) return emptyLibrary;
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return emptyLibrary;
  }
  if (!isObj(raw) || raw.version !== LIBRARY_VERSION) return emptyLibrary;
  const list = (v: unknown) => (Array.isArray(v) ? v.filter(isObj) : []);
  const saved = list(raw.saved)
    .filter(s => isStr(s.id) && isStr(s.name) && isStr(s.url) && isStr(s.app) && isStr(s.savedAt))
    .map(
      s =>
        ({
          id: s.id,
          name: s.name,
          url: s.url,
          app: s.app,
          savedAt: s.savedAt,
        }) as SavedState,
    );
  const seen = new Set<string>();
  const recent = capRecent(
    list(raw.recent)
      .filter(r => isStr(r.url) && isStr(r.app) && isStr(r.visitedAt) && !seen.has(r.url) && !!seen.add(r.url))
      .map(r => ({ url: r.url, app: r.app, visitedAt: r.visitedAt }) as RecentState)
      .filter(r => utf8Length(r.url) <= MAX_RECENT_URL_BYTES),
  );
  const sites = list(raw.sites)
    .filter(s => isStr(s.cid) && isStr(s.name) && isStr(s.addedAt))
    .map(s => ({ cid: s.cid, name: s.name, addedAt: s.addedAt }) as SavedSite);
  return { version: LIBRARY_VERSION, saved, recent, sites };
}

/** The JSON text to persist. */
export function serializeLibrary(lib: Library): string {
  return JSON.stringify({
    version: lib.version,
    saved: lib.saved,
    recent: lib.recent,
    sites: lib.sites,
  });
}
