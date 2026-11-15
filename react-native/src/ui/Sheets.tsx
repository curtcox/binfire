// Modal sheets: show text, error, save name, send menu, CID loading and
// chooser, and the HashBin save sheets (spec/ui.md "Sheets").
import * as Clipboard from 'expo-clipboard';
import { createContext, useContext, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Linking,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { utf8Length } from '../core/bytes';
import type { RegistryApp } from '../core/config';
import { LONG_LINK_BYTES } from '../core/hashbin';
import { parseUrl } from '../core/url';
import { colors, common } from './theme';

const SheetCloseRef = createContext<{ current: () => void } | null>(null);

/**
 * The one modal that hosts every sheet. Switching from one sheet to another
 * swaps only the content: presenting a new iOS modal while the previous one
 * is still dismissing can leave an empty, touch-blocking modal behind.
 */
export function SheetHost({ open, children }: { open: boolean; children: ReactNode }) {
  const closeRef = useRef<() => void>(() => undefined);
  if (!open) return null;
  return (
    <Modal transparent animationType="slide" onRequestClose={() => closeRef.current()} visible>
      {/* Android apps run edge-to-edge (RN 0.88), so the window does not resize for the
          keyboard and the sheet must pad itself on both platforms. */}
      <KeyboardAvoidingView style={sheetStyles.root} behavior="padding">
        <Pressable style={sheetStyles.scrim} onPress={() => closeRef.current()} accessible={false} />
        <SheetCloseRef.Provider value={closeRef}>{children}</SheetCloseRef.Provider>
      </KeyboardAvoidingView>
    </Modal>
  );
}

/** One sheet's panel inside `SheetHost`; `onClose` handles the scrim and Android back. */
export function Sheet({ testID, onClose, children }: { testID: string; onClose: () => void; children: ReactNode }) {
  const insets = useSafeAreaInsets();
  const closeRef = useContext(SheetCloseRef);
  useLayoutEffect(() => {
    if (closeRef) closeRef.current = onClose;
  }, [closeRef, onClose]);
  return (
    <View testID={testID} style={[sheetStyles.sheet, { paddingBottom: 16 + insets.bottom }]}>
      {children}
    </View>
  );
}

const PREVIEW_CHARS = 2000;

/** Shows text binfire won't open. Offers Open in browser (http/https only) and Copy. */
export function TextSheet({ text, onClose }: { text: string; onClose: () => void }) {
  const url = parseUrl(text);
  const isWeb = !!url && (url.scheme === 'http' || url.scheme === 'https');
  const [copied, setCopied] = useState(false);
  return (
    <Sheet testID="text.sheet" onClose={onClose}>
      <Text style={sheetStyles.title}>Not a binfire app</Text>
      <Text style={sheetStyles.body}>binfire only opens registered apps. You can open this in your browser or copy it.</Text>
      <Text testID="text.value" style={sheetStyles.value} selectable numberOfLines={8}>
        {text.length > PREVIEW_CHARS ? text.slice(0, PREVIEW_CHARS) + '…' : text}
      </Text>
      <View style={sheetStyles.row}>
        {isWeb && (
          <Pressable
            testID="text.openBrowser"
            style={common.button}
            onPress={() => {
              Linking.openURL(text).catch(() => undefined);
              onClose();
            }}
          >
            <Text style={common.buttonText}>Open in browser</Text>
          </Pressable>
        )}
        <Pressable
          testID="text.copy"
          style={common.ghostButton}
          onPress={() => {
            Clipboard.setStringAsync(text).then(
              () => setCopied(true),
              () => undefined,
            );
          }}
        >
          <Text style={common.ghostButtonText}>{copied ? 'Copied' : 'Copy'}</Text>
        </Pressable>
        <Pressable style={common.ghostButton} onPress={onClose}>
          <Text style={common.ghostButtonText}>Close</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

export function ErrorSheet({ message, onClose }: { message: string; onClose: () => void }) {
  return (
    <Sheet testID="error.sheet" onClose={onClose}>
      <Text style={sheetStyles.title}>{"Can't open that"}</Text>
      <Text testID="error.message" style={sheetStyles.body}>
        {message}
      </Text>
      <View style={sheetStyles.row}>
        <Pressable testID="error.ok" style={common.button} onPress={onClose}>
          <Text style={common.buttonText}>OK</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

/** Asks for a name, then saves. An empty name uses `fallbackName`. */
export function SaveSheet({
  fallbackName,
  onSave,
  onClose,
}: {
  fallbackName: string;
  onSave: (name: string) => void;
  onClose: () => void;
}) {
  const [name, setName] = useState('');
  const confirm = () => onSave(name.trim() || fallbackName);
  return (
    <Sheet testID="save.sheet" onClose={onClose}>
      <Text style={sheetStyles.title}>Save state</Text>
      <TextInput
        testID="save.name"
        style={common.input}
        value={name}
        onChangeText={setName}
        placeholder={fallbackName}
        autoFocus
        returnKeyType="done"
        onSubmitEditing={confirm}
        maxLength={200}
      />
      <View style={sheetStyles.row}>
        <Pressable testID="save.confirm" style={common.button} onPress={confirm}>
          <Text style={common.buttonText}>Save</Text>
        </Pressable>
        <Pressable testID="save.cancel" style={common.ghostButton} onPress={onClose}>
          <Text style={common.ghostButtonText}>Cancel</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

function copyText(text: string, done: () => void) {
  Clipboard.setStringAsync(text).then(done, () => undefined);
}

/** A plain menu row. */
export function MenuItem({ testID, label, onPress, disabled }: { testID: string; label: string; onPress: () => void; disabled?: boolean }) {
  return (
    <Pressable
      testID={testID}
      style={[common.ghostButton, sheetStyles.menuItem, disabled && sheetStyles.disabled]}
      disabled={disabled}
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={label}
    >
      <Text style={common.ghostButtonText}>{label}</Text>
    </Pressable>
  );
}

/**
 * The send menu: Copy link (with the long-link notice past `LONG_LINK_BYTES`),
 * Save to HashBin when a client ID is configured, and Sign out of HashBin.
 */
export function SendSheet({
  link,
  canSave,
  signedIn,
  onSave,
  onQr,
  onSignOut,
  onClose,
}: {
  link: string | null;
  /** A client ID is configured (Native Save is available). */
  canSave: boolean;
  signedIn: boolean;
  /** Runs Native Save; `copy` copies the resulting `/c#` link. */
  onSave: (copy: boolean) => void;
  /** Opens the QR sheet for `link`. */
  onQr: () => void;
  onSignOut: () => void;
  onClose: () => void;
}) {
  const [copied, setCopied] = useState(false);
  const long = !!link && utf8Length(link) > LONG_LINK_BYTES;
  return (
    <Sheet testID="send.sheet" onClose={onClose}>
      <Text style={sheetStyles.title}>Send</Text>
      <MenuItem
        testID="send.copy"
        label={copied ? 'Link copied' : 'Copy link'}
        disabled={!link}
        onPress={() => link && copyText(link, () => setCopied(true))}
      />
      {link && (
        <Text style={sheetStyles.muted} numberOfLines={2}>
          {link}
        </Text>
      )}
      {copied && long && (
        <View testID="long.notice" style={sheetStyles.notice}>
          <Text style={sheetStyles.body}>
            This link is long, and some messengers and mail apps cut long links off. Save to HashBin for a short link.
          </Text>
          <Pressable testID="long.save" style={common.button} onPress={() => onSave(true)} accessibilityRole="button">
            <Text style={common.buttonText}>Save to HashBin</Text>
          </Pressable>
        </View>
      )}
      <MenuItem testID="send.qr" label="QR code" disabled={!link} onPress={onQr} />
      {canSave && <MenuItem testID="send.hashbin" label="Save to HashBin" onPress={() => onSave(false)} />}
      {canSave && signedIn && <MenuItem testID="hashbin.signOut" label="Sign out of HashBin" onPress={onSignOut} />}
      <View style={sheetStyles.row}>
        <Pressable style={common.ghostButton} onPress={onClose}>
          <Text style={common.ghostButtonText}>Done</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

/** Shown while a CID is fetched and verified. Closing it abandons the load. */
export function LoadingSheet({ onClose }: { onClose: () => void }) {
  return (
    <Sheet testID="loading.sheet" onClose={onClose}>
      <View style={sheetStyles.busyRow}>
        <ActivityIndicator color={colors.accent} />
        <Text style={sheetStyles.body}>Loading document…</Text>
      </View>
      <View style={sheetStyles.row}>
        <Pressable style={common.ghostButton} onPress={onClose}>
          <Text style={common.ghostButtonText}>Cancel</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

/** Which app opens a loaded document, plus Copy link and Open raw. */
export function ChooserSheet({
  apps,
  matched,
  link,
  rawUrl,
  onPick,
  onClose,
}: {
  apps: readonly RegistryApp[];
  /** True when `apps` are the apps for this document type (several); false when none matched. */
  matched: boolean;
  link: string;
  rawUrl: string;
  onPick: (app: RegistryApp) => void;
  onClose: () => void;
}) {
  const [copied, setCopied] = useState(false);
  return (
    <Sheet testID="chooser.sheet" onClose={onClose}>
      <Text style={sheetStyles.title}>Open with</Text>
      <Text style={sheetStyles.body}>
        {matched ? 'Several apps can open this document.' : "binfire couldn't tell which app made this document."}
      </Text>
      <ScrollView style={sheetStyles.list} contentContainerStyle={sheetStyles.listContent}>
        {apps.map(app => (
          <MenuItem key={app.slug} testID={`chooser.app.${app.slug}`} label={app.name} onPress={() => onPick(app)} />
        ))}
      </ScrollView>
      <View style={sheetStyles.row}>
        <Pressable testID="chooser.copy" style={common.ghostButton} onPress={() => copyText(link, () => setCopied(true))}>
          <Text style={common.ghostButtonText}>{copied ? 'Copied' : 'Copy link'}</Text>
        </Pressable>
        <Pressable
          testID="chooser.raw"
          style={common.ghostButton}
          onPress={() => {
            Linking.openURL(rawUrl).catch(() => undefined);
            onClose();
          }}
        >
          <Text style={common.ghostButtonText}>Open raw</Text>
        </Pressable>
        <Pressable style={common.ghostButton} onPress={onClose}>
          <Text style={common.ghostButtonText}>Cancel</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} bytes`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KiB`;
  return `${(n / 1024 / 1024).toFixed(1)} MiB`;
}

/** Size and estimated cost, then Save/Cancel. `estimate` is undefined while loading, null if unknown. */
export function HashbinConfirmSheet({
  size,
  estimate,
  maxCostCents,
  busy,
  onOk,
  onClose,
}: {
  size: number;
  estimate: number | null | undefined;
  /** The cap sent as max_cost_cents; shown as "up to" when there is no estimate. */
  maxCostCents: number;
  /** Signing in; Save is disabled. */
  busy: boolean;
  onOk: () => void;
  onClose: () => void;
}) {
  const cost =
    estimate === undefined
      ? 'Estimating cost…'
      : estimate === null
        ? `Cost: up to $${(maxCostCents / 100).toFixed(2)} (charged to your HashBin balance)`
        : estimate === 0
          ? 'Estimated cost: free'
          : `Estimated cost: up to ${estimate}¢ (charged to your HashBin balance)`;
  return (
    <Sheet testID="hashbin.confirm" onClose={onClose}>
      <Text style={sheetStyles.title}>Save to HashBin</Text>
      <Text testID="hashbin.size" style={sheetStyles.body}>
        {`Size: ${formatBytes(size)}`}
      </Text>
      <Text testID="hashbin.cost" style={sheetStyles.muted}>
        {cost}
      </Text>
      <View style={sheetStyles.row}>
        <Pressable
          testID="hashbin.ok"
          style={[common.button, busy && sheetStyles.disabled]}
          disabled={busy}
          onPress={onOk}
          accessibilityRole="button"
        >
          <Text style={common.buttonText}>{busy ? 'Signing in…' : 'Save'}</Text>
        </Pressable>
        <Pressable testID="hashbin.cancel" style={common.ghostButton} onPress={onClose} accessibilityRole="button">
          <Text style={common.ghostButtonText}>Cancel</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

export function HashbinBusySheet() {
  return (
    <Sheet testID="hashbin.busy" onClose={() => undefined}>
      <View style={sheetStyles.busyRow}>
        <ActivityIndicator color={colors.accent} />
        <Text style={sheetStyles.body}>Saving to HashBin…</Text>
      </View>
    </Sheet>
  );
}

/** The `/c#` link of a saved document. */
export function HashbinResultSheet({ link, copied, onClose }: { link: string; copied: boolean; onClose: () => void }) {
  const [isCopied, setCopied] = useState(copied);
  return (
    <Sheet testID="hashbin.result" onClose={onClose}>
      <Text style={sheetStyles.title}>Saved to HashBin</Text>
      <Text testID="hashbin.link" style={sheetStyles.value} selectable>
        {link}
      </Text>
      <View style={sheetStyles.row}>
        <Pressable testID="hashbin.copy" style={common.button} onPress={() => copyText(link, () => setCopied(true))}>
          <Text style={common.buttonText}>{isCopied ? 'Link copied' : 'Copy link'}</Text>
        </Pressable>
        <Pressable style={common.ghostButton} onPress={onClose}>
          <Text style={common.ghostButtonText}>Done</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

/** For states binfire can't extract: the app's own Publish makes the link. */
export function PublishNoteSheet({ onClose }: { onClose: () => void }) {
  return (
    <Sheet testID="hashbin.publishNote" onClose={onClose}>
      <Text style={sheetStyles.title}>{"Use the app's Publish"}</Text>
      <Text style={sheetStyles.body}>
        {"binfire can't read this app's document from its link. Use the app's own Publish (Save to HashBin) button to get a short link."}
      </Text>
      <View style={sheetStyles.row}>
        <Pressable style={common.button} onPress={onClose}>
          <Text style={common.buttonText}>OK</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

export const sheetStyles = StyleSheet.create({
  root: { flex: 1, justifyContent: 'flex-end' },
  scrim: { ...StyleSheet.absoluteFill, backgroundColor: colors.scrim },
  sheet: {
    backgroundColor: colors.bg,
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    padding: 16,
    gap: 12,
  },
  title: { fontSize: 18, fontWeight: '700', color: colors.text },
  body: { fontSize: 15, color: colors.text },
  value: {
    fontSize: 14,
    fontFamily: Platform.select({ ios: 'Menlo', default: 'monospace' }),
    color: colors.text,
    backgroundColor: colors.surface,
    padding: 10,
    borderRadius: 8,
  },
  muted: { fontSize: 13, color: colors.muted },
  row: { flexDirection: 'row', gap: 8, flexWrap: 'wrap' },
  menuItem: { alignItems: 'flex-start' },
  disabled: { opacity: 0.5 },
  notice: { gap: 8, padding: 12, borderRadius: 8, backgroundColor: colors.banner },
  busyRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 8 },
  list: { maxHeight: 320 },
  listContent: { gap: 8 },
});
