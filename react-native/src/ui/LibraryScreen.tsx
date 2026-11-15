// Library (home): open field, Apps / Saved / Recent tabs (spec/ui.md).
import * as Clipboard from 'expo-clipboard';
import { useState } from 'react';
import { Alert, FlatList, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { Registry, RegistryApp } from '../core/config';
import type { Library, RecentState, SavedState } from '../core/library';
import { appForSlug } from '../core/registry';
import { classifyState } from '../core/state';
import { colors, common } from './theme';

type Tab = 'apps' | 'saved' | 'recent';

const URL_PREVIEW = 120;

function preview(url: string): string {
  return url.length > URL_PREVIEW ? url.slice(0, URL_PREVIEW) + '…' : url;
}

function when(iso: string): string {
  const d = new Date(iso);
  return isNaN(d.getTime()) ? '' : d.toLocaleString();
}

export interface LibraryScreenProps {
  registry: Registry;
  library: Library;
  /** Routes typed text (and saved/recent URLs) with route(). */
  onOpenText: (text: string) => void;
  /** Routes pasted text with routeShared(), which finds a link inside words. */
  onPasteText: (text: string) => void;
  onOpenApp: (app: RegistryApp) => void;
  onDeleteSaved: (id: string) => void;
  /** Opens the scan sheet. */
  onScan: () => void;
}

export function LibraryScreen({
  registry,
  library,
  onOpenText,
  onPasteText,
  onOpenApp,
  onDeleteSaved,
  onScan,
}: LibraryScreenProps) {
  const insets = useSafeAreaInsets();
  const [input, setInput] = useState('');
  const [tab, setTab] = useState<Tab>('apps');

  const go = () => onOpenText(input);
  const paste = async () => {
    const text = await Clipboard.getStringAsync().catch(() => '');
    if (!text) return; // empty clipboard: nothing
    setInput(text);
    onPasteText(text);
  };

  const appName = (slug: string) => appForSlug(slug, registry)?.name ?? slug;

  const confirmDelete = (s: SavedState) =>
    Alert.alert('Delete saved state?', s.name, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => onDeleteSaved(s.id),
      },
    ]);

  return (
    <View style={[styles.root, { paddingTop: insets.top + 8 }]}>
      <Text style={styles.heading} accessibilityRole="header">
        binfire
      </Text>
      <View style={styles.openRow}>
        <TextInput
          testID="open.input"
          style={[common.input, styles.openInput]}
          value={input}
          onChangeText={setInput}
          placeholder="Paste a link or CID"
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="url"
          returnKeyType="go"
          onSubmitEditing={go}
        />
        <Pressable testID="open.go" style={common.button} onPress={go} accessibilityLabel="Open">
          <Text style={common.buttonText}>Open</Text>
        </Pressable>
        <Pressable testID="open.paste" style={common.ghostButton} onPress={paste} accessibilityLabel="Paste">
          <Text style={common.ghostButtonText}>Paste</Text>
        </Pressable>
        <Pressable testID="open.scan" style={common.ghostButton} onPress={onScan} accessibilityLabel="Scan">
          <Text style={common.ghostButtonText}>Scan</Text>
        </Pressable>
      </View>

      <View style={styles.tabs} accessibilityRole="tablist">
        {(['apps', 'saved', 'recent'] as const).map(t => (
          <Pressable
            key={t}
            testID={`tab.${t}`}
            accessibilityRole="tab"
            accessibilityState={{ selected: tab === t }}
            style={[styles.tab, tab === t && styles.tabSelected]}
            onPress={() => setTab(t)}
          >
            <Text style={[styles.tabText, tab === t && styles.tabTextSelected]}>
              {t === 'apps' ? 'Apps' : t === 'saved' ? 'Saved' : 'Recent'}
            </Text>
          </Pressable>
        ))}
      </View>

      {tab === 'apps' && (
        <FlatList
          key="apps"
          data={registry.apps}
          keyExtractor={a => a.slug}
          numColumns={3}
          contentContainerStyle={[styles.list, { paddingBottom: insets.bottom + 16 }]}
          columnWrapperStyle={styles.tileRow}
          renderItem={({ item }) => (
            <Pressable
              testID={`app.${item.slug}`}
              style={styles.tile}
              onPress={() => onOpenApp(item)}
              accessibilityRole="button"
              accessibilityLabel={item.name}
            >
              <View style={styles.tileIcon}>
                <Text style={styles.tileLetter}>{item.name.slice(0, 1)}</Text>
              </View>
              <Text style={styles.tileName} numberOfLines={1}>
                {item.name}
              </Text>
            </Pressable>
          )}
        />
      )}

      {tab === 'saved' && (
        <FlatList
          key="saved"
          data={library.saved as SavedState[]}
          keyExtractor={s => s.id}
          contentContainerStyle={[styles.list, { paddingBottom: insets.bottom + 16 }]}
          ListEmptyComponent={<Text style={styles.empty}>No saved states yet. Use Save in an app.</Text>}
          renderItem={({ item, index }) => (
            <Pressable
              testID={`saved.row.${index}`}
              style={styles.row}
              onPress={() => onOpenText(item.url)}
              onLongPress={() => confirmDelete(item)}
              accessible
              accessibilityRole="button"
              accessibilityLabel={`${item.name}, ${appName(item.app)} · ${when(item.savedAt)}`}
              accessibilityHint="Long-press to delete"
            >
              <Text style={styles.rowTitle} numberOfLines={1}>
                {item.name}
              </Text>
              <Text style={styles.rowSub} numberOfLines={1}>
                {appName(item.app)} · {when(item.savedAt)}
              </Text>
              <Text style={styles.rowUrl} numberOfLines={1}>
                {preview(item.url)}
              </Text>
            </Pressable>
          )}
        />
      )}

      {tab === 'recent' && (
        <FlatList
          key="recent"
          data={library.recent as RecentState[]}
          keyExtractor={r => r.url}
          contentContainerStyle={[styles.list, { paddingBottom: insets.bottom + 16 }]}
          ListEmptyComponent={<Text style={styles.empty}>Nothing opened yet.</Text>}
          renderItem={({ item, index }) => (
            <Pressable
              testID={`recent.row.${index}`}
              style={styles.row}
              onPress={() => onOpenText(item.url)}
              accessible
              accessibilityRole="button"
              accessibilityLabel={`${appName(item.app)} · ${classifyState(item.url).state}, ${when(item.visitedAt)}`}
            >
              <Text style={styles.rowTitle} numberOfLines={1}>
                {appName(item.app)} · {classifyState(item.url).state}
              </Text>
              <Text style={styles.rowSub} numberOfLines={1}>
                {when(item.visitedAt)}
              </Text>
              <Text style={styles.rowUrl} numberOfLines={1}>
                {preview(item.url)}
              </Text>
            </Pressable>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.bg, paddingHorizontal: 16 },
  heading: {
    fontSize: 28,
    fontWeight: '800',
    color: colors.text,
    marginBottom: 12,
  },
  openRow: { flexDirection: 'row', gap: 8, alignItems: 'center' },
  openInput: { flex: 1 },
  tabs: { flexDirection: 'row', marginTop: 16, gap: 8 },
  tab: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 16,
    backgroundColor: colors.surface,
  },
  tabSelected: { backgroundColor: colors.text },
  tabText: { color: colors.text, fontWeight: '500' },
  tabTextSelected: { color: colors.bg },
  list: { paddingTop: 16, gap: 8 },
  tileRow: { gap: 8 },
  tile: {
    flex: 1 / 3,
    alignItems: 'center',
    paddingVertical: 12,
    borderRadius: 12,
    backgroundColor: colors.surface,
  },
  tileIcon: {
    width: 48,
    height: 48,
    borderRadius: 12,
    backgroundColor: colors.accent,
    alignItems: 'center',
    justifyContent: 'center',
  },
  tileLetter: { color: colors.accentText, fontSize: 22, fontWeight: '700' },
  tileName: { marginTop: 6, color: colors.text, fontSize: 13 },
  row: {
    padding: 12,
    borderRadius: 10,
    backgroundColor: colors.surface,
    gap: 2,
  },
  rowTitle: { fontSize: 15, fontWeight: '600', color: colors.text },
  rowSub: { fontSize: 12, color: colors.muted },
  rowUrl: { fontSize: 12, color: colors.muted },
  empty: { color: colors.muted, textAlign: 'center', marginTop: 32 },
});
