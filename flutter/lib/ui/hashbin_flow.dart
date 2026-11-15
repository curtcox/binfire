/// HashBin in the UI: opening a `load-cid` route (loading sheet, chooser),
/// Send → Copy link with the long-link offer, and Native Save (confirm,
/// sign-in, upload, result). spec/cid.md, spec/hashbin.md, spec/ui.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/core.dart';
import 'binfire_controller.dart';
import 'ids.dart';
import 'sheets.dart';

/// A user-facing message for a `loadCID` error code.
String cidErrorMessage(String code) => switch (code) {
      ErrorCodes.network => "Couldn't reach HashBin. Check that you're online and try again.",
      ErrorCodes.notFound => 'This document was not found. It may have expired or been deleted.',
      ErrorCodes.unavailable => 'This document is unavailable for legal reasons.',
      ErrorCodes.rateLimited => 'HashBin is getting too many requests. Try again in a moment.',
      ErrorCodes.tooLarge => 'This document is too large to open.',
      ErrorCodes.mismatch => "This document failed verification: its content doesn't match its ID.",
      ErrorCodes.invalidCid => "This isn't a valid document ID.",
      ErrorCodes.httpError => "HashBin's content server returned an error. Try again later.",
      _ => 'Opening this document failed ($code).',
    };

/// A user-facing message for a Native Save error code.
String hashbinErrorMessage(String code) => switch (code) {
      ErrorCodes.insufficientBalance => 'Your HashBin balance is too low. Add funds at hashbin.org, then try again.',
      ErrorCodes.costExceeded => 'Saving would cost more than the estimate, so nothing was saved or charged.',
      ErrorCodes.tooLarge => 'This document is too large for HashBin.',
      ErrorCodes.mismatch => "HashBin returned an ID that doesn't match this document, so binfire didn't use it.",
      ErrorCodes.failed => "Signing in to HashBin didn't work. Try again.",
      ErrorCodes.unauthorized => 'Your HashBin sign-in has expired. Try again to sign in.',
      ErrorCodes.network => "Couldn't reach HashBin. Check that you're online and try again.",
      _ => 'Saving to HashBin failed ($code).',
    };

String _formatBytes(int n) {
  if (n < 1000) return '$n bytes';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)} KB';
  return '${(n / 1000000).toStringAsFixed(1)} MB';
}

String _formatCents(int c) => c < 100 ? '$c¢' : '\$${(c / 100).toStringAsFixed(2)}';

Widget _sheet(BuildContext context, String id, List<Widget> children) => withId(
      id,
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );

Widget _buttons(List<Widget> buttons) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: buttons),
    );

/// Runs [work] behind a non-dismissible sheet tagged [id], then removes it.
Future<T> _behindSheet<T>(BuildContext context, String id, String label, Future<T> Function() work) async {
  final nav = Navigator.of(context);
  final route = ModalBottomSheetRoute<void>(
    isScrollControlled: false,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => PopScope(
      canPop: false,
      child: _sheet(context, id, [
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        Text(label, textAlign: TextAlign.center),
        const SizedBox(height: 8),
      ]),
    ),
  );
  nav.push(route);
  try {
    return await work();
  } finally {
    if (route.isActive) nav.removeRoute(route);
  }
}

// ---------------------------------------------------------------------------
// Opening a loaded document (cid.md)
// ---------------------------------------------------------------------------

/// Performs a `load-cid` route: loads and verifies [cid], then opens the
/// hinted or single matching app at `canonicalOrigin#cid`, or shows the
/// chooser. Errors show the error sheet.
Future<void> openCid(BuildContext context, BinfireController c, String cid, {String? hint}) async {
  final Uint8List bytes;
  try {
    bytes = await _behindSheet(context, Ids.loadingSheet, 'Loading from HashBin…', () => c.fetchCid(cid));
  } on BinfireException catch (e) {
    if (context.mounted) await showErrorSheet(context, cidErrorMessage(e.code));
    return;
  }
  if (!context.mounted) return;
  final hinted = hint == null ? null : c.registry.bySlug(hint);
  if (hinted != null) {
    c.openApp(hinted.slug, '${hinted.canonicalOrigin}#$cid');
    return;
  }
  final type = documentType(bytes);
  final apps = type == null ? const <RegistryApp>[] : appsForDocumentType(c.registry, type);
  if (apps.length == 1) {
    c.openApp(apps.single.slug, '${apps.single.canonicalOrigin}#$cid');
    return;
  }
  await showChooserSheet(context, c, cid, apps.isEmpty ? c.registry.apps : apps);
}

/// The chooser: [apps], plus **Copy link** and **Open raw**.
Future<void> showChooserSheet(BuildContext context, BinfireController c, String cid, List<RegistryApp> apps) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.8),
      child: _sheet(sheet, Ids.chooserSheet, [
        Text('Open with', style: Theme.of(sheet).textTheme.titleMedium),
        const SizedBox(height: 8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final app in apps)
                withId(
                  Ids.chooserApp(app.slug),
                  ListTile(
                    title: Text(app.name),
                    onTap: () {
                      Navigator.pop(sheet);
                      c.openApp(app.slug, '${app.canonicalOrigin}#$cid');
                    },
                  ),
                ),
            ],
          ),
        ),
        _buttons([
          withId(
            Ids.chooserRaw,
            TextButton(
              onPressed: () {
                Navigator.pop(sheet);
                launchUrl(Uri.parse(c.contentUrl(cid)), mode: LaunchMode.externalApplication);
              },
              child: const Text('Open raw'),
            ),
          ),
          withId(
            Ids.chooserCopy,
            FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: c.links.makeCidLink(cid)));
                Navigator.pop(sheet);
              },
              child: const Text('Copy link'),
            ),
          ),
        ]),
      ]),
    ),
  );
}

// ---------------------------------------------------------------------------
// Send → Copy link, and the long-link offer (hashbin.md)
// ---------------------------------------------------------------------------

/// **Copy link**: copies `makeLink` of [slug]'s current URL. A link longer
/// than [longLinkBytes] also shows the long-link notice.
Future<void> copyLink(BuildContext context, BinfireController c, String slug) async {
  final o = c.openFor(slug);
  final link = o == null ? null : c.links.makeLink(o.currentUrl);
  if (link == null) return;
  await Clipboard.setData(ClipboardData(text: link));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Link copied')));
  if (!isLongLink(link)) return;
  final save = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => _sheet(sheet, Ids.longNotice, [
      Text('This link is long', style: Theme.of(sheet).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        'The link was copied, but it is ${_formatBytes(utf8Length(link))} long. '
        'Messengers and mail apps may cut it short. '
        '${c.canSaveToHashbin ? 'Save the document to HashBin to get a short link.' : "Use the app's own Publish button to get a short link."}',
      ),
      _buttons([
        TextButton(onPressed: () => Navigator.pop(sheet, false), child: const Text('OK')),
        if (c.canSaveToHashbin)
          withId(
            Ids.longSave,
            FilledButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Save to HashBin for a short link')),
          ),
      ]),
    ]),
  );
  if (save == true && context.mounted) await saveToHashbin(context, c, slug, copyResult: true);
}

// ---------------------------------------------------------------------------
// Native Save (hashbin.md)
// ---------------------------------------------------------------------------

/// **Save to HashBin** for [slug]'s current state: links an existing CID,
/// uploads a `v1` document after confirmation and sign-in, or explains the
/// app's own Publish. With [copyResult] the `/c#` link is also copied.
Future<void> saveToHashbin(BuildContext context, BinfireController c, String slug, {bool copyResult = false}) async {
  final client = c.hashbin;
  final authenticate = c.authenticate;
  final o = c.openFor(slug);
  if (client == null || authenticate == null || o == null) return;
  final what = saveBytesFor(o.currentUrl, limits: c.config.limits);
  switch (what.kind) {
    case SaveKind.none:
      await showPublishNote(context);
      return;
    case SaveKind.cid:
      final link = c.links.makeCidLink(what.cid!, slug);
      if (copyResult) await Clipboard.setData(ClipboardData(text: link));
      if (context.mounted) await showHashbinResult(context, link);
      return;
    case SaveKind.text:
    case SaveKind.json:
      break;
  }
  final bytes = what.bytes!;
  if (!context.mounted) return;
  final maxCost = await showHashbinConfirm(context, bytes.length, client.fetchConfig());
  if (maxCost == null || !context.mounted) return;
  final UploadResult result;
  try {
    result = await _behindSheet(
      context,
      'hashbin.saving',
      'Saving to HashBin…',
      () => client.save(bytes, what.contentType!, authenticate: authenticate, maxCostCents: maxCost),
    );
  } on BinfireException catch (e) {
    c.hashbinChanged();
    if (e.code != ErrorCodes.cancelled && context.mounted) await showErrorSheet(context, hashbinErrorMessage(e.code));
    return;
  }
  c.hashbinChanged();
  final link = c.links.makeCidLink(result.cid, slug);
  if (copyResult) await Clipboard.setData(ClipboardData(text: link));
  if (context.mounted) await showHashbinResult(context, link);
}

/// Shows the size and estimated cost and asks to save. Returns the
/// `max_cost_cents` cap to upload with, or `null` when cancelled.
Future<int?> showHashbinConfirm(BuildContext context, int size, Future<HashbinPricing?> pricing) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => _sheet(sheet, Ids.hashbinConfirm, [
      Text('Save to HashBin', style: Theme.of(sheet).textTheme.titleMedium),
      const SizedBox(height: 8),
      withId(Ids.hashbinSize, Text('Size: ${_formatBytes(size)}')),
      FutureBuilder<HashbinPricing?>(
        future: pricing,
        builder: (context, snap) {
          final done = snap.connectionState == ConnectionState.done;
          final p = snap.data;
          final estimate = p?.estimateCents(size);
          final tooLarge = p?.maxUploadBytes != null && size > p!.maxUploadBytes!;
          final cap = estimate ?? defaultMaxCostCents;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(!done
                  ? 'Estimating cost…'
                  : estimate != null
                      ? 'Estimated cost: ${_formatCents(estimate)} (one month)'
                      : 'HashBin will charge at most ${_formatCents(cap)}.'),
              if (tooLarge) const Text('This is larger than HashBin accepts.'),
              const SizedBox(height: 8),
              const Text('HashBin is pay-to-publish. You may be asked to sign in.'),
              _buttons([
                withId(Ids.hashbinCancel, TextButton(onPressed: () => Navigator.pop(sheet), child: const Text('Cancel'))),
                withId(
                  Ids.hashbinOk,
                  FilledButton(
                    onPressed: done && !tooLarge ? () => Navigator.pop(sheet, cap) : null,
                    child: const Text('Save'),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
    ]),
  );
}

/// Shows the saved document's `/c#` [link] with **Copy**.
Future<void> showHashbinResult(BuildContext context, String link) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => _sheet(sheet, Ids.hashbinResult, [
      Text('Saved to HashBin', style: Theme.of(sheet).textTheme.titleMedium),
      const SizedBox(height: 8),
      withId(Ids.hashbinLink, Text(link)),
      _buttons([
        TextButton(onPressed: () => Navigator.pop(sheet), child: const Text('Done')),
        withId(
          Ids.hashbinCopy,
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(sheet);
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Link copied')));
            },
            child: const Text('Copy'),
          ),
        ),
      ]),
    ]),
  );
}

/// Explains that this state can only be saved by the app's own Publish.
Future<void> showPublishNote(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => _sheet(sheet, Ids.hashbinPublishNote, [
      Text('Use the app to publish', style: Theme.of(sheet).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text(
        "binfire can't read this document by itself. Use the app's own Save or Publish to HashBin button to get a short link.",
      ),
      _buttons([FilledButton(onPressed: () => Navigator.pop(sheet), child: const Text('OK'))]),
    ]),
  );
}
