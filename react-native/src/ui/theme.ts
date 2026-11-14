import { StyleSheet } from 'react-native';

export const colors = {
  bg: '#ffffff',
  surface: '#f3f4f6',
  border: '#d1d5db',
  text: '#111827',
  muted: '#6b7280',
  accent: '#c2410c',
  accentText: '#ffffff',
  banner: '#fef3c7',
  danger: '#b91c1c',
  scrim: 'rgba(0,0,0,0.35)',
};

export const common = StyleSheet.create({
  button: {
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 8,
    backgroundColor: colors.accent,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonText: { color: colors.accentText, fontWeight: '600', fontSize: 15 },
  ghostButton: {
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: 8,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ghostButtonText: { color: colors.text, fontWeight: '500', fontSize: 15 },
  input: {
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 15,
    color: colors.text,
    backgroundColor: colors.bg,
  },
});
