// Root UI: library and browsers, with every input going through route().
import { randomUUID } from 'expo-crypto';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import * as Linking from 'expo-linking';
import { useShareIntent } from 'expo-share-intent';
import { BackHandler, StyleSheet, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { defaultContext, type RegistryApp } from '../core/config';
import { addRecent, addSaved, removeSaved, type Library } from '../core/library';
import { makeLink, route, routeShared, withoutRun, type Route } from '../core/links';
import { parseUrl } from '../core/url';
import { appForUrl } from '../core/registry';
import { classifyState } from '../core/state';
import { BrowserScreen, type BrowserState } from './BrowserScreen';
import { LibraryScreen } from './LibraryScreen';
import { ErrorSheet, SaveSheet, SendSheet, TextSheet } from './Sheets';
import { loadLibrary, storeLibrary } from './storage';
import { colors } from './theme';

const ctx = defaultContext;

type Sheet =
  { kind: 'text'; text: string } | { kind: 'error'; message: string } | { kind: 'save' } | { kind: 'send' } | null;

const ERROR_MESSAGES: Record<string, string> = {
  'too-large': 'That text is too large to open.',
  'unknown-app': "That link is for an app binfire doesn't know.",
  'bad-link': 'That binfire link is malformed.',
  'unknown-link': "That binfire link isn't one binfire understands.",
  'invalid-cid': "That link's document ID (CID) isn't valid.",
};

export default function BinfireApp() {
  const [library, setLibrary] = useState<Library>(loadLibrary);
  const [browsers, setBrowsers] = useState<Record<string, BrowserState>>({});
  const [active, setActive] = useState<string | null>(null);
  const [screen, setScreen] = useState<'library' | 'browser'>('library');
  const [sheet, setSheet] = useState<Sheet>(null);

  // Persist library changes, coalescing bursts (e.g. typing in an app).
  const firstRender = useRef(true);
  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    const t = setTimeout(() => void storeLibrary(library), 300);
    return () => clearTimeout(t);
  }, [library]);

  const recordVisit = useCallback((slug: string, url: string) => {
    setLibrary(lib => (lib.recent[0]?.url === url ? lib : addRecent(lib, url, slug)));
  }, []);

  /** Opens (or reuses) the browser for `slug` at `url`. */
  const openApp = useCallback(
    (slug: string, url: string) => {
      setBrowsers(prev => {
        const existing = prev[slug];
        let next: BrowserState;
        if (!existing) next = { source: url, current: url, generation: 0 };
        else if (existing.source !== url) next = { ...existing, source: url, current: url };
        else if (existing.current !== url)
          next = {
            ...existing,
            current: url,
            generation: existing.generation + 1,
          };
        else next = existing;
        return next === existing ? prev : { ...prev, [slug]: next };
      });
      setActive(slug);
      setScreen('browser');
      setSheet(null);
      recordVisit(slug, url);
    },
    [recordVisit],
  );

  const handleRoute = useCallback(
    (r: Route) => {
      switch (r.action) {
        case 'open-app':
          return openApp(r.app, r.url);
        case 'show-text':
          return setSheet({ kind: 'text', text: r.text });
        case 'error':
          return setSheet({
            kind: 'error',
            message: ERROR_MESSAGES[r.error] ?? r.error,
          });
        case 'load-cid':
          return setSheet({
            kind: 'error',
            message: 'Opening HashBin documents by CID is coming in M3.',
          });
        case 'open-site':
          return setSheet({
            kind: 'error',
            message: 'Packaged sites are coming in M6.',
          });
      }
    },
    [openApp],
  );

  const openText = useCallback((text: string) => handleRoute(route(text, ctx)), [handleRoute]);
  const openShared = useCallback((text: string) => handleRoute(routeShared(text, ctx)), [handleRoute]);

  // Tapped links in: custom scheme, Universal/App Links, and `.binfire` file opens.
  const openIncomingUrl = useCallback(
    (url: string) => {
      const parsed = parseUrl(url);
      const scheme = parsed?.scheme;
      // expo-share-intent's own hand-off from the iOS Share Extension; the hook below handles it.
      if (url.toLowerCase().startsWith(`${ctx.config.scheme.toLowerCase()}://dataurl=`)) return;
      if (scheme === 'file' || scheme === 'content') {
        setSheet({ kind: 'error', message: 'Opening .binfire files is coming in M5.' });
        return;
      }
      handleRoute(route(url, ctx));
    },
    [handleRoute],
  );
  const openIncomingRef = useRef(openIncomingUrl);
  useEffect(() => {
    openIncomingRef.current = openIncomingUrl;
  }, [openIncomingUrl]);
  useEffect(() => {
    let cancelled = false;
    Linking.getInitialURL().then(
      url => {
        if (url && !cancelled) openIncomingRef.current(url);
      },
      () => undefined,
    );
    const sub = Linking.addEventListener('url', ({ url }) => openIncomingRef.current(url));
    return () => {
      cancelled = true;
      sub.remove();
    };
  }, []);

  // Share target in (iOS Share Extension, Android ACTION_SEND).
  const { hasShareIntent, shareIntent, resetShareIntent } = useShareIntent({ resetOnBackground: true });
  useEffect(() => {
    if (!hasShareIntent) return;
    const text = shareIntent.text ?? shareIntent.webUrl;
    // The share intent is an external event delivered through the hook's state, so routing it here is intended.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (text) openShared(text);
    else if (shareIntent.files?.length) setSheet({ kind: 'error', message: 'Opening shared files is coming in M5.' });
    resetShareIntent();
  }, [hasShareIntent, shareIntent, resetShareIntent, openShared]);

  const openTile = useCallback(
    (app: RegistryApp) => {
      if (browsers[app.slug]) {
        setActive(app.slug);
        setScreen('browser');
      } else openApp(app.slug, app.canonicalOrigin);
    },
    [browsers, openApp],
  );

  const onUrlChange = useCallback(
    (slug: string, url: string) => {
      setBrowsers(prev => {
        const b = prev[slug];
        return !b || b.current === url ? prev : { ...prev, [slug]: { ...b, current: url } };
      });
      // Only the app's own URLs are states; about:blank and HashBin pages are not.
      if (appForUrl(url, ctx.registry)?.slug === slug) recordVisit(slug, url);
    },
    [recordVisit],
  );

  const onBlocked = useCallback(
    (url: string) => {
      const r = route(url, ctx);
      // Another registered app opens in its own browser; anything else is only shown.
      if (r.action === 'open-app') openApp(r.app, r.url);
      else setSheet({ kind: 'text', text: url });
    },
    [openApp],
  );

  const current = active ? browsers[active]?.current : undefined;

  const onRun = useCallback(() => {
    if (!active || !current) return;
    openApp(active, withoutRun(current));
  }, [active, current, openApp]);

  const onSave = useCallback(
    (name: string) => {
      if (active && current) setLibrary(lib => addSaved(lib, { id: randomUUID(), name, url: current, app: active }));
      setSheet(null);
    },
    [active, current],
  );

  useEffect(() => {
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      if (sheet) {
        setSheet(null);
        return true;
      }
      if (screen === 'browser') {
        setScreen('library');
        return true;
      }
      return false;
    });
    return () => sub.remove();
  }, [sheet, screen]);

  const fallbackName =
    active && current
      ? `${ctx.registry.apps.find(a => a.slug === active)?.name ?? active} · ${classifyState(current).state}`
      : '';

  return (
    <SafeAreaProvider>
      <StatusBar style="dark" />
      <View style={styles.root}>
        <LibraryScreen
          registry={ctx.registry}
          library={library}
          onOpenText={openText}
          onPasteText={openShared}
          onOpenApp={openTile}
          onDeleteSaved={id => setLibrary(lib => removeSaved(lib, id))}
        />
        <BrowserScreen
          ctx={ctx}
          browsers={browsers}
          active={active}
          visible={screen === 'browser'}
          onUrlChange={onUrlChange}
          onBlocked={onBlocked}
          onLibrary={() => setScreen('library')}
          onSave={() => setSheet({ kind: 'save' })}
          onSend={() => setSheet({ kind: 'send' })}
          onRun={onRun}
        />
      </View>
      {sheet?.kind === 'text' && <TextSheet text={sheet.text} onClose={() => setSheet(null)} />}
      {sheet?.kind === 'error' && <ErrorSheet message={sheet.message} onClose={() => setSheet(null)} />}
      {sheet?.kind === 'save' && (
        <SaveSheet fallbackName={fallbackName} onSave={onSave} onClose={() => setSheet(null)} />
      )}
      {sheet?.kind === 'send' && (
        <SendSheet link={current ? makeLink(current, ctx) : null} onClose={() => setSheet(null)} />
      )}
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.bg },
});
