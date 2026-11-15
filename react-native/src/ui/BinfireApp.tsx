// Root UI: library and browsers, with every input going through route().
import { randomUUID } from 'expo-crypto';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import * as Linking from 'expo-linking';
import { useShareIntent } from 'expo-share-intent';
import * as Clipboard from 'expo-clipboard';
import { BackHandler, Platform, StyleSheet, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { type RegistryApp } from '../core/config';
import { documentType } from '../core/envelope';
import { isBinfireError } from '../core/errors';
import { contentUrl, estimateCostCents, isOAuthCallback, loadCid, saveBytes } from '../core/hashbin';
import { addRecent, addSaved, removeSaved, type Library } from '../core/library';
import { makeCidLink, makeLink, route, routeShared, withoutRun, type Route } from '../core/links';
import { parseUrl } from '../core/url';
import { appForSlug, appForUrl, appsForDocumentType } from '../core/registry';
import { classifyState } from '../core/state';
import { BrowserScreen, type BrowserState } from './BrowserScreen';
import { LibraryScreen } from './LibraryScreen';
import { appContext, contentFetch, hashbinClient } from './hashbinPlatform';
import {
  ChooserSheet,
  ErrorSheet,
  HashbinBusySheet,
  HashbinConfirmSheet,
  HashbinResultSheet,
  LoadingSheet,
  PublishNoteSheet,
  SaveSheet,
  SendSheet,
  SheetHost,
  TextSheet,
} from './Sheets';
import { loadLibrary, storeLibrary } from './storage';
import { colors } from './theme';

const ctx = appContext;

type Sheet =
  | { kind: 'text'; text: string }
  | { kind: 'error'; message: string }
  | { kind: 'save' }
  | { kind: 'send'; signedIn: boolean }
  | { kind: 'loading' }
  | { kind: 'chooser'; cid: string; apps: readonly RegistryApp[]; matched: boolean }
  | {
      kind: 'hashbinConfirm';
      bytes: Uint8Array;
      contentType: string;
      slug: string;
      copy: boolean;
      /** undefined while `/api/config` loads. */
      estimate?: number | null;
      maxUpload?: number;
      /** Signing in: the auth session is up. */
      busy?: boolean;
    }
  | { kind: 'hashbinBusy' }
  | { kind: 'hashbinResult'; link: string; copied: boolean }
  | { kind: 'publishNote' }
  | null;

const ERROR_MESSAGES: Record<string, string> = {
  'too-large': 'That text is too large to open.',
  'unknown-app': "That link is for an app binfire doesn't know.",
  'bad-link': 'That binfire link is malformed.',
  'unknown-link': "That binfire link isn't one binfire understands.",
  'invalid-cid': "That link's document ID (CID) isn't valid.",
  // CID load (spec/cid.md) and HashBin save (spec/hashbin.md).
  network: "Couldn't reach HashBin. Check your connection and try again.",
  'not-found': 'That document was not found. It may have expired or been deleted.',
  unavailable: 'That document is unavailable (removed after a dispute).',
  'rate-limited': 'HashBin is limiting requests for that document. Try again later.',
  'http-error': 'HashBin returned an error. Try again later.',
  mismatch: "The document didn't match its ID (CID), so binfire won't open it.",
  failed: "Couldn't sign in to HashBin. Try again.",
  'insufficient-balance': 'Your HashBin balance is too low for this save. Add funds on hashbin.org and try again.',
  'cost-exceeded': 'This save would cost more than the configured limit, so HashBin did not charge you.',
};
const SIZE_MESSAGES = {
  load: 'That document is too large to open.',
  save: 'That document is too large to save to HashBin.',
};

function errorMessage(e: unknown, op: keyof typeof SIZE_MESSAGES): string {
  if (!isBinfireError(e)) {
    // An unexpected platform error (e.g. the Keychain refused the tokens). Its message never holds token values.
    const detail = e instanceof Error && e.message ? ` (${e.message.slice(0, 200)})` : '';
    return (op === 'save' ? 'Saving to HashBin failed.' : "Couldn't open that document.") + detail;
  }
  if (e.code === 'too-large') return SIZE_MESSAGES[op];
  return ERROR_MESSAGES[e.code] ?? e.code;
}

const wait = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));
/** Lets a dismissing iOS sheet finish before another view controller is presented. */
const PRESENT_DELAY_MS = Platform.OS === 'ios' ? 600 : 50;

/**
 * expo-share-intent's iOS hand-off URL (`<scheme>://dataUrl=…`); its hook handles it.
 * The plugin always uses the first configured scheme (the public one); the own
 * scheme is accepted too in case that changes.
 */
function isShareHandoff(url: string): boolean {
  const lower = url.toLowerCase();
  return [ctx.config.scheme, ctx.config.ownScheme].some(s => lower.startsWith(`${s.toLowerCase()}://dataurl=`));
}

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

  // Each load gets a number; closing the loading sheet abandons the current one.
  const loadSeq = useRef(0);
  const loadDocument = useCallback(
    async (cid: string, hint: string | null) => {
      const seq = ++loadSeq.current;
      setSheet({ kind: 'loading' });
      try {
        const bytes = await loadCid(cid, ctx.config.limits.maxStateBytes, contentFetch, ctx);
        if (seq !== loadSeq.current) return;
        const hinted = hint ? appForSlug(hint, ctx.registry) : null;
        const type = documentType(bytes);
        const apps = hinted ? [hinted] : type ? appsForDocumentType(type, ctx.registry) : [];
        if (apps.length === 1) openApp(apps[0].slug, `${apps[0].canonicalOrigin}#${cid}`);
        else setSheet({ kind: 'chooser', cid, apps: apps.length ? apps : ctx.registry.apps, matched: apps.length > 0 });
      } catch (e) {
        if (seq === loadSeq.current) setSheet({ kind: 'error', message: errorMessage(e, 'load') });
      }
    },
    [openApp],
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
          return void loadDocument(r.cid, r.app);
        case 'open-site':
          return setSheet({
            kind: 'error',
            message: 'Packaged sites are coming in M6.',
          });
      }
    },
    [openApp, loadDocument],
  );

  const openText = useCallback((text: string) => handleRoute(route(text, ctx)), [handleRoute]);
  const openShared = useCallback((text: string) => handleRoute(routeShared(text, ctx)), [handleRoute]);

  // Tapped links in: custom scheme, Universal/App Links, and `.binfire` file opens.
  const openIncomingUrl = useCallback(
    (url: string) => {
      const parsed = parseUrl(url);
      const scheme = parsed?.scheme;
      // expo-share-intent's own hand-off from the iOS Share Extension; the hook below handles it.
      if (isShareHandoff(url)) return;
      // The OAuth redirect belongs to the auth session (Android also delivers it as a link).
      if (isOAuthCallback(url, ctx)) return;
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
    // A link that arrived before JS subscribed (cold start, or right after
    // launch while the bundle loads) is dropped by the 'url' event, but
    // expo-linking keeps the latest one natively: read it once, then clear it.
    const pending = Linking.getLinkingURL();
    if (pending) {
      if (!isShareHandoff(pending)) Linking.clearInitialURL();
      // (openIncomingUrl ignores an OAuth redirect.)
      openIncomingRef.current(pending);
    } else {
      Linking.getInitialURL().then(
        url => {
          if (url && !cancelled) openIncomingRef.current(url);
        },
        () => undefined,
      );
    }
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

  const showSaved = useCallback((link: string, copy: boolean) => {
    if (copy) Clipboard.setStringAsync(link).catch(() => undefined);
    setSheet({ kind: 'hashbinResult', link, copied: copy });
  }, []);

  /** Native Save of the current state (spec/hashbin.md "What is saved for a state"). */
  const startSave = useCallback(
    (copy: boolean) => {
      if (!active || !current) return;
      // Without a client ID, Native Save is off: point at the app's own Publish.
      if (!hashbinClient) return setSheet({ kind: 'publishNote' });
      const what = saveBytes(current, ctx.config.limits.maxStateBytes);
      if (what.kind === 'cid') return showSaved(makeCidLink(what.cid, active, ctx), copy);
      if (what.kind === 'none') return setSheet({ kind: 'publishNote' });
      const { bytes } = what;
      setSheet({ kind: 'hashbinConfirm', bytes, contentType: what.contentType, slug: active, copy });
      hashbinClient.apiConfig().then(cfg => {
        const maxUpload = typeof cfg?.max_upload_bytes === 'number' ? cfg.max_upload_bytes : undefined;
        setSheet(s =>
          s?.kind === 'hashbinConfirm' && s.bytes === bytes
            ? { ...s, estimate: estimateCostCents(bytes.length, cfg), maxUpload }
            : s,
        );
      });
    },
    [active, current, showSaved],
  );

  const confirmSave = useCallback(async () => {
    if (sheet?.kind !== 'hashbinConfirm' || sheet.busy || !hashbinClient) return;
    const { bytes, contentType, slug, copy, maxUpload } = sheet;
    const client = hashbinClient;
    if (maxUpload !== undefined && bytes.length > maxUpload) {
      setSheet({ kind: 'error', message: SIZE_MESSAGES.save });
      return;
    }
    // Always the configured cap, never an estimate (spec/hashbin.md "Cost").
    const cap = ctx.config.hashbin.maxCostCents;
    try {
      if (!(await client.accessToken())) {
        setSheet(s => (s?.kind === 'hashbinConfirm' ? { ...s, busy: true } : s));
        // The system auth session presents over the confirm sheet, which stays
        // up meanwhile; let the session's own UI finish dismissing afterwards.
        await client.signIn();
        await wait(PRESENT_DELAY_MS);
      }
      setSheet({ kind: 'hashbinBusy' });
      const result = await client.save(bytes, contentType, cap);
      showSaved(makeCidLink(result.cid, slug, ctx), copy);
    } catch (e) {
      if (isBinfireError(e, 'cancelled')) setSheet(null);
      else setSheet({ kind: 'error', message: errorMessage(e, 'save') });
    }
  }, [sheet, showSaved]);

  const openSend = useCallback(() => {
    setSheet({ kind: 'send', signedIn: false });
    hashbinClient?.isSignedIn().then(
      signedIn => setSheet(s => (s?.kind === 'send' ? { ...s, signedIn } : s)),
      () => undefined,
    );
  }, []);

  const signOut = useCallback(() => {
    hashbinClient?.signOut().catch(() => undefined);
    setSheet(s => (s?.kind === 'send' ? { ...s, signedIn: false } : s));
  }, []);

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
          onSend={openSend}
          onRun={onRun}
        />
      </View>
      <SheetHost open={sheet !== null}>
        {sheet?.kind === 'text' && <TextSheet text={sheet.text} onClose={() => setSheet(null)} />}
        {sheet?.kind === 'error' && <ErrorSheet message={sheet.message} onClose={() => setSheet(null)} />}
        {sheet?.kind === 'save' && (
          <SaveSheet fallbackName={fallbackName} onSave={onSave} onClose={() => setSheet(null)} />
        )}
        {sheet?.kind === 'send' && (
          <SendSheet
            link={current ? makeLink(current, ctx) : null}
            canSave={!!hashbinClient}
            signedIn={sheet.signedIn}
            onSave={startSave}
            onSignOut={signOut}
            onClose={() => setSheet(null)}
          />
        )}
        {sheet?.kind === 'loading' && (
          <LoadingSheet
            onClose={() => {
              loadSeq.current++;
              setSheet(null);
            }}
          />
        )}
        {sheet?.kind === 'chooser' && (
          <ChooserSheet
            apps={sheet.apps}
            matched={sheet.matched}
            link={makeCidLink(sheet.cid, null, ctx)}
            rawUrl={contentUrl(sheet.cid, ctx)}
            onPick={app => openApp(app.slug, `${app.canonicalOrigin}#${sheet.cid}`)}
            onClose={() => setSheet(null)}
          />
        )}
        {sheet?.kind === 'hashbinConfirm' && (
          <HashbinConfirmSheet
            size={sheet.bytes.length}
            estimate={sheet.estimate}
            maxCostCents={ctx.config.hashbin.maxCostCents}
            busy={!!sheet.busy}
            onOk={() => void confirmSave()}
            onClose={() => setSheet(null)}
          />
        )}
        {sheet?.kind === 'hashbinBusy' && <HashbinBusySheet />}
        {sheet?.kind === 'hashbinResult' && (
          <HashbinResultSheet link={sheet.link} copied={sheet.copied} onClose={() => setSheet(null)} />
        )}
        {sheet?.kind === 'publishNote' && <PublishNoteSheet onClose={() => setSheet(null)} />}
      </SheetHost>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.bg },
});
