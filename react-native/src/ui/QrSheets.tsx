// QR display, multi-frame QR and scanning sheets (spec/qr.md "UI").
import { CameraView, Camera, scanFromURLAsync, type BarcodeScanningResult } from 'expo-camera';
import * as Device from 'expo-device';
import { File, Paths } from 'expo-file-system';
import * as ImagePicker from 'expo-image-picker';
import * as Sharing from 'expo-sharing';
import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import Svg, { Path, Rect } from 'react-native-svg';
import type { BinfireContext } from '../core/config';
import { qrMatrix, qrPlan, qrPng, QR_QUIET_ZONE, type QrMatrix } from '../core/qr';
import { ScanSession, type ScanResult } from '../transfer/scan';
import { MenuItem, Sheet, sheetStyles } from './Sheets';
import { colors, common } from './theme';

/** One SVG path for the dark modules, a run of modules per row segment. */
function modulesPath(m: QrMatrix): string {
  let d = '';
  for (let y = 0; y < m.size; y++) {
    let x = 0;
    while (x < m.size) {
      if (!m.dark(x, y)) {
        x++;
        continue;
      }
      const start = x;
      while (x < m.size && m.dark(x, y)) x++;
      d += `M${start + QR_QUIET_ZONE} ${y + QR_QUIET_ZONE}h${x - start}v1h${start - x}z`;
    }
  }
  return d;
}

/** Black modules on white with a 4-module quiet zone, in any theme. */
const QrImage = memo(function QrImage({ matrix, size, testID }: { matrix: QrMatrix; size: number; testID: string }) {
  const n = matrix.size + 2 * QR_QUIET_ZONE;
  const d = useMemo(() => modulesPath(matrix), [matrix]);
  return (
    <View testID={testID} accessible accessibilityRole="image" accessibilityLabel="QR code" style={styles.qrBox}>
      <Svg width={size} height={size} viewBox={`0 0 ${n} ${n}`}>
        <Rect x={0} y={0} width={n} height={n} fill="#ffffff" />
        <Path d={d} fill="#000000" />
      </Svg>
    </View>
  );
});

function useQrSize(): number {
  const { width, height } = useWindowDimensions();
  return Math.max(160, Math.min(width - 32, height * 0.5, 360));
}

/** Writes the QR as a PNG (8 px per module) to a temporary file and opens the share sheet. */
async function shareQrPng(matrix: QrMatrix): Promise<void> {
  const file = new File(Paths.cache, 'binfire-qr.png');
  if (file.exists) file.delete();
  await file.write(qrPng(matrix, 8));
  await Sharing.shareAsync(file.uri, { mimeType: 'image/png', UTI: 'public.png', dialogTitle: 'Share QR code' });
}

/**
 * The QR sheet for a link: the QR (plans ok and dense), the dense or too-long
 * note, Save to HashBin and Multi-frame QR (dense and too-long), and Share.
 */
export function QrSheet({
  text,
  canMulti,
  onHashbin,
  onMulti,
  onClose,
}: {
  /** The `makeLink` link (or a saved `/c#` link). */
  text: string;
  /** Multi-frame needs the raw app URL; false for a saved `/c#` link. */
  canMulti: boolean;
  onHashbin: () => void;
  onMulti: () => void;
  onClose: () => void;
}) {
  const plan = qrPlan(text);
  const matrix = useMemo(() => (plan === 'too-long' ? null : qrMatrix(text)), [plan, text]);
  const size = useQrSize();
  const [shareError, setShareError] = useState<string | null>(null);
  return (
    <Sheet testID="qr.sheet" onClose={onClose}>
      <Text style={sheetStyles.title}>QR code</Text>
      {matrix && <QrImage testID="qr.image" matrix={matrix} size={size} />}
      {plan !== 'ok' && (
        <Text testID="qr.note" style={sheetStyles.body}>
          {plan === 'dense'
            ? 'This QR code is dense, so it may be hard to scan. Save to HashBin for a short link, or use a multi-frame QR.'
            : 'This link is too long for one QR code. Save to HashBin for a short link, or use a multi-frame QR.'}
        </Text>
      )}
      {plan !== 'ok' && <MenuItem testID="qr.hashbin" label="Save to HashBin" onPress={onHashbin} />}
      {plan !== 'ok' && canMulti && <MenuItem testID="qr.multi" label="Multi-frame QR" onPress={onMulti} />}
      {shareError && <Text style={sheetStyles.muted}>{shareError}</Text>}
      <View style={sheetStyles.row}>
        {matrix && (
          <Pressable
            testID="qr.export"
            style={common.button}
            accessibilityRole="button"
            onPress={() => {
              setShareError(null);
              shareQrPng(matrix).catch(() => setShareError("Couldn't share the image."));
            }}
          >
            <Text style={common.buttonText}>Share image</Text>
          </Pressable>
        )}
        <Pressable testID="qr.close" style={common.ghostButton} onPress={onClose} accessibilityRole="button">
          <Text style={common.ghostButtonText}>Done</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

const FRAME_MS = 200; // 5 frames per second
const FRAME_CACHE_MAX = 400;

/** QR symbols of the frame texts, computed on first show and kept (up to a bound). */
class FrameMatrices {
  private readonly cache = new Map<number, QrMatrix>();
  constructor(private readonly texts: readonly string[]) {}

  get(i: number): QrMatrix {
    const hit = this.cache.get(i);
    if (hit) return hit;
    // Every frame text fits version 20-L (spec/qr.md), so this is never null.
    const m = qrMatrix(this.texts[i])!;
    if (this.cache.size < FRAME_CACHE_MAX) this.cache.set(i, m);
    return m;
  }
}

/** Cycles the `BF1:` frames `0, 1, …, n-1, 0, …` at 5 fps with an `i/n` counter. */
export function QrFramesSheet({ texts, onClose }: { texts: readonly string[]; onClose: () => void }) {
  const [index, setIndex] = useState(0);
  const size = useQrSize();
  const cache = useMemo(() => new FrameMatrices(texts), [texts]);
  useEffect(() => {
    const t = setInterval(() => setIndex(i => (i + 1) % texts.length), FRAME_MS);
    return () => clearInterval(t);
  }, [texts]);
  const i = index % texts.length;
  const matrix = cache.get(i);
  return (
    <Sheet testID="qr.multiSheet" onClose={onClose}>
      <Text style={sheetStyles.title}>Multi-frame QR</Text>
      <Text style={sheetStyles.body}>Scan with binfire on the other device and hold steady until every frame is in.</Text>
      <QrImage testID="qr.frames" matrix={matrix} size={size} />
      <Text testID="qr.frameIndex" style={[sheetStyles.body, styles.counter]}>
        {`${i + 1}/${texts.length}`}
      </Text>
      <View style={sheetStyles.row}>
        <Pressable style={common.ghostButton} onPress={onClose} accessibilityRole="button">
          <Text style={common.ghostButtonText}>Done</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

const FRAME_ERRORS: Record<string, string> = {
  'bad-frame': "That code isn't a valid binfire frame.",
  'bad-magic': "That code isn't a binfire frame.",
  'bad-version': 'That frame is from a newer version of binfire.',
  'too-large': 'That transfer is too large.',
  inconsistent: 'Frames from different transfers were mixed. Start again.',
  mismatch: "The received data didn't match its ID (CID). Start again.",
};

type CameraState = 'checking' | 'ready' | 'unavailable' | 'denied';

/** What the scan sheet hands back: a route or a complete bundle payload. */
export type ScanOutcome = Extract<ScanResult, { kind: 'route' } | { kind: 'bundle' }>;

/**
 * Live camera (when there is one and permission is granted) plus Scan from
 * image. Every decoded text goes to one `ScanSession` for the sheet's life.
 */
export function ScanSheet({
  ctx,
  onOutcome,
  onClose,
}: {
  ctx: BinfireContext;
  /** Called once, with the first route or bundle; the caller closes the sheet. */
  onOutcome: (outcome: ScanOutcome) => void;
  onClose: () => void;
}) {
  const [session] = useState(() => new ScanSession(ctx));
  const done = useRef(false);
  // Simulators and emulators count as having no camera (spec/qr.md).
  const [camera, setCamera] = useState<CameraState>(Device.isDevice ? 'checking' : 'unavailable');
  const [status, setStatus] = useState<string | null>(null);
  const [picking, setPicking] = useState(false);

  useEffect(() => {
    let cancelled = false;
    if (!Device.isDevice) return;
    Camera.requestCameraPermissionsAsync().then(
      p => !cancelled && setCamera(p.granted ? 'ready' : 'denied'),
      () => !cancelled && setCamera('unavailable'),
    );
    return () => {
      cancelled = true;
    };
  }, []);

  const accept = useCallback(
    (text: string) => {
      if (done.current) return;
      const result = session.accept(text);
      switch (result.kind) {
        case 'progress':
          return setStatus(`Receiving ${result.received} of ${result.count}`);
        case 'frame-error':
          return setStatus(FRAME_ERRORS[result.error] ?? `Frame error: ${result.error}`);
        default:
          done.current = true;
          onOutcome(result);
      }
    },
    [onOutcome, session],
  );

  const onBarcode = useCallback((r: BarcodeScanningResult) => accept(r.data), [accept]);

  const fromImage = useCallback(async () => {
    if (picking) return;
    setPicking(true);
    try {
      // The system picker needs no camera or photo-library permission.
      const picked = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 1 });
      if (picked.canceled || !picked.assets?.length) return;
      const found = await scanFromURLAsync(picked.assets[0].uri, ['qr']);
      if (!found.length) setStatus('No QR code found in this image.');
      else accept(found[0].data);
    } catch {
      setStatus("Couldn't read that image.");
    } finally {
      setPicking(false);
    }
  }, [accept, picking]);

  const cameraMessage =
    camera === 'unavailable' ? 'Camera unavailable' : camera === 'denied' ? 'Camera permission denied' : null;
  const size = useQrSize();

  return (
    <Sheet testID="scan.sheet" onClose={onClose}>
      <Text style={sheetStyles.title}>Scan a QR code</Text>
      {camera === 'ready' && (
        <View style={[styles.cameraBox, { height: size }]}>
          <CameraView
            testID="scan.camera"
            style={StyleSheet.absoluteFill}
            facing="back"
            barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
            onBarcodeScanned={onBarcode}
            onMountError={() => setCamera('unavailable')}
          />
        </View>
      )}
      <Text testID="scan.status" style={sheetStyles.body}>
        {status ?? cameraMessage ?? (camera === 'checking' ? 'Starting camera…' : 'Point the camera at a QR code.')}
      </Text>
      {status && cameraMessage && <Text style={sheetStyles.muted}>{cameraMessage}</Text>}
      <View style={sheetStyles.row}>
        <Pressable
          testID="scan.image"
          style={[common.button, picking && sheetStyles.disabled]}
          disabled={picking}
          onPress={() => void fromImage()}
          accessibilityRole="button"
        >
          <Text style={common.buttonText}>Scan from image</Text>
        </Pressable>
        <Pressable testID="scan.cancel" style={common.ghostButton} onPress={onClose} accessibilityRole="button">
          <Text style={common.ghostButtonText}>Cancel</Text>
        </Pressable>
      </View>
    </Sheet>
  );
}

const styles = StyleSheet.create({
  qrBox: { alignSelf: 'center', backgroundColor: '#ffffff' },
  counter: { alignSelf: 'center', fontVariant: ['tabular-nums'] },
  cameraBox: { borderRadius: 12, overflow: 'hidden', backgroundColor: colors.text },
});
