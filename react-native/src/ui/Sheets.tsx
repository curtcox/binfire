// Modal sheets: show text, error, save name, send menu (spec/ui.md "Sheets").
import * as Clipboard from 'expo-clipboard';
import { useState, type ReactNode } from 'react';
import {
  KeyboardAvoidingView,
  Linking,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { parseUrl } from '../core/url';
import { colors, common } from './theme';

function Sheet({ testID, onClose, children }: { testID: string; onClose: () => void; children: ReactNode }) {
  const insets = useSafeAreaInsets();
  return (
    <Modal transparent animationType="slide" onRequestClose={onClose} visible>
      <KeyboardAvoidingView style={styles.root} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <Pressable style={styles.scrim} onPress={onClose} accessible={false} />
        <View testID={testID} style={[styles.sheet, { paddingBottom: 16 + insets.bottom }]}>
          {children}
        </View>
      </KeyboardAvoidingView>
    </Modal>
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
      <Text style={styles.title}>Not a binfire app</Text>
      <Text style={styles.body}>binfire only opens registered apps. You can open this in your browser or copy it.</Text>
      <Text testID="text.value" style={styles.value} selectable numberOfLines={8}>
        {text.length > PREVIEW_CHARS ? text.slice(0, PREVIEW_CHARS) + '…' : text}
      </Text>
      <View style={styles.row}>
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
      <Text style={styles.title}>{"Can't open that"}</Text>
      <Text testID="error.message" style={styles.body}>
        {message}
      </Text>
      <View style={styles.row}>
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
      <Text style={styles.title}>Save state</Text>
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
      <View style={styles.row}>
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

/** The send menu. M1 has only Copy link; QR, file and nearby come later. */
export function SendSheet({ link, onClose }: { link: string | null; onClose: () => void }) {
  const [copied, setCopied] = useState(false);
  return (
    <Sheet testID="send.sheet" onClose={onClose}>
      <Text style={styles.title}>Send</Text>
      <Pressable
        testID="send.copyLink"
        style={[common.ghostButton, styles.menuItem]}
        disabled={!link}
        onPress={() => {
          if (link)
            Clipboard.setStringAsync(link).then(
              () => setCopied(true),
              () => undefined,
            );
        }}
      >
        <Text style={common.ghostButtonText}>{copied ? 'Link copied' : 'Copy link'}</Text>
      </Pressable>
      {link && (
        <Text style={styles.muted} numberOfLines={2}>
          {link}
        </Text>
      )}
      <View style={styles.row}>
        <Pressable style={common.ghostButton} onPress={onClose}>
          <Text style={common.ghostButtonText}>Done</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

const styles = StyleSheet.create({
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
});
