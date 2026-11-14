// Browser: one live WebView per opened app, kept mounted while hidden so each
// app keeps its page state, storage and drafts (spec/ui.md "Browser").
import { useCallback, useRef } from "react";
import { Platform, Pressable, StyleSheet, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { WebView, type WebViewNavigation } from "react-native-webview";
import type { ShouldStartLoadRequest } from "react-native-webview/lib/WebViewTypes";
import type { BinfireContext } from "../core/config";
import { decideNavigation } from "../core/navigation";
import { appForSlug } from "../core/registry";
import { classifyState } from "../core/state";
import { colors, common } from "./theme";

/** One app's browser. `source` is what the WebView was told to load; `current` tracks the main frame. */
export interface BrowserState {
  source: string;
  current: string;
  /** Bumped to force a fresh load of `source` (remounts the WebView). */
  generation: number;
}

export interface BrowserScreenProps {
  ctx: BinfireContext;
  browsers: Readonly<Record<string, BrowserState>>;
  active: string | null;
  visible: boolean;
  onUrlChange: (slug: string, url: string) => void;
  /** A main-frame navigation that was cancelled by the policy. */
  onBlocked: (url: string) => void;
  onLibrary: () => void;
  onSave: () => void;
  onSend: () => void;
  onRun: () => void;
}

function AppWebView({
  slug,
  state,
  active,
  ctx,
  onUrlChange,
  onBlocked,
  registerRef,
}: {
  slug: string;
  state: BrowserState;
  active: boolean;
  ctx: BinfireContext;
  onUrlChange: (slug: string, url: string) => void;
  onBlocked: (url: string) => void;
  registerRef: (slug: string, ref: { reload: () => void } | null) => void;
}) {
  const onShouldStart = useCallback(
    (req: ShouldStartLoadRequest): boolean => {
      // Policy applies to the main frame only. (Android only reports main-frame loads.)
      if (Platform.OS === "ios" && req.isTopFrame === false) return true;
      const decision = decideNavigation(req.url, slug, ctx);
      if (!decision.allow) setTimeout(() => onBlocked(decision.url), 0);
      return decision.allow;
    },
    [slug, ctx, onBlocked],
  );
  const onNav = useCallback(
    (nav: WebViewNavigation) => {
      if (nav.url) onUrlChange(slug, nav.url);
    },
    [slug, onUrlChange],
  );
  return (
    <View
      style={[StyleSheet.absoluteFill, !active && styles.hidden]}
      pointerEvents={active ? "auto" : "none"}
    >
      <WebView
        key={state.generation}
        ref={(ref) => registerRef(slug, ref)}
        testID={active ? "web.view" : undefined}
        source={{ uri: state.source }}
        // Every URL reaches the policy; the library default would hand
        // non-http(s) schemes to the OS (an auto-navigation PLAN §10 forbids).
        originWhitelist={["*"]}
        onShouldStartLoadWithRequest={onShouldStart}
        onNavigationStateChange={onNav}
        // HashBin Publish opens a popup. Android can keep the opener with
        // multiple windows; on iOS react-native-webview cannot, so Publish
        // falls back to the redirect flow (spec/hashbin.md).
        setSupportMultipleWindows
        javaScriptCanOpenWindowsAutomatically
        allowsBackForwardNavigationGestures
        allowsInlineMediaPlayback
        webviewDebuggingEnabled={__DEV__}
        style={styles.webview}
      />
    </View>
  );
}

export function BrowserScreen(props: BrowserScreenProps) {
  const { ctx, browsers, active, visible } = props;
  const insets = useSafeAreaInsets();
  const refs = useRef(new Map<string, { reload: () => void }>());
  const registerRef = useCallback((slug: string, ref: { reload: () => void } | null) => {
    if (ref) refs.current.set(slug, ref);
    else refs.current.delete(slug);
  }, []);

  const state = active ? browsers[active] : undefined;
  const app = active ? appForSlug(active, ctx.registry) : null;
  const info = state ? classifyState(state.current) : null;
  const title = app && info ? `${app.name} · ${info.state}` : "";

  return (
    <View
      style={[styles.root, !visible && styles.hidden]}
      pointerEvents={visible ? "auto" : "none"}
      accessibilityElementsHidden={!visible}
      importantForAccessibility={visible ? "auto" : "no-hide-descendants"}
    >
      {visible && (
        <View style={[styles.bar, { paddingTop: insets.top + 4 }]}>
          <Pressable
            testID="web.library"
            style={styles.barButton}
            onPress={props.onLibrary}
            accessibilityLabel="Library"
          >
            <Text style={styles.barButtonText}>‹ Library</Text>
          </Pressable>
          <Text testID="web.title" style={styles.title} numberOfLines={1}>
            {title}
          </Text>
          <Pressable
            testID="web.reload"
            style={styles.barButton}
            onPress={() => active && refs.current.get(active)?.reload()}
            accessibilityLabel="Reload"
          >
            <Text style={styles.barButtonText}>↻</Text>
          </Pressable>
          <Pressable
            testID="web.save"
            style={styles.barButton}
            onPress={props.onSave}
            accessibilityLabel="Save"
          >
            <Text style={styles.barButtonText}>Save</Text>
          </Pressable>
          <Pressable
            testID="web.send"
            style={styles.barButton}
            onPress={props.onSend}
            accessibilityLabel="Send"
          >
            <Text style={styles.barButtonText}>Send</Text>
          </Pressable>
        </View>
      )}
      {visible && info && !info.run && (
        <View testID="run.banner" style={styles.banner}>
          <Text style={styles.bannerText}>
            {"Code isn't running. Run it when you trust this state."}
          </Text>
          <Pressable
            testID="run.go"
            style={common.button}
            onPress={props.onRun}
            accessibilityLabel="Run"
          >
            <Text style={common.buttonText}>Run</Text>
          </Pressable>
        </View>
      )}
      <View style={styles.webArea}>
        {Object.entries(browsers).map(([slug, s]) => (
          <AppWebView
            key={slug}
            slug={slug}
            state={s}
            active={visible && slug === active}
            ctx={ctx}
            onUrlChange={props.onUrlChange}
            onBlocked={props.onBlocked}
            registerRef={registerRef}
          />
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { ...StyleSheet.absoluteFill, backgroundColor: colors.bg },
  hidden: { opacity: 0, zIndex: -1 },
  bar: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 8,
    paddingBottom: 6,
    gap: 4,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
    backgroundColor: colors.bg,
  },
  barButton: { paddingHorizontal: 8, paddingVertical: 8 },
  barButtonText: { color: colors.accent, fontSize: 15, fontWeight: "600" },
  title: {
    flex: 1,
    textAlign: "center",
    fontSize: 15,
    fontWeight: "600",
    color: colors.text,
  },
  banner: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    padding: 12,
    backgroundColor: colors.banner,
  },
  bannerText: { flex: 1, color: colors.text, fontSize: 14 },
  webArea: { flex: 1 },
  webview: { flex: 1 },
});
