/// Modal sheets: show text, error, save name (spec/ui.md, Sheets).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ids.dart';

/// Longest text shown in full; larger texts are truncated for display.
const _maxShownChars = 4000;

String _preview(String text) =>
    text.length <= _maxShownChars ? text : '${text.substring(0, _maxShownChars)}…';

bool _isHttpUrl(String text) {
  final t = text.toLowerCase();
  return t.startsWith('https://') || t.startsWith('http://');
}

/// Shows text binfire won't open, with **Open in browser** (for http(s)
/// URLs) and **Copy**. Never navigates on its own.
Future<void> showTextSheet(BuildContext context, String text) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => withId(
      Ids.textSheet,
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Not a binfire app', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(child: withId(Ids.textValue, Text(_preview(text)))),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_isHttpUrl(text))
                    withId(
                      Ids.textOpenBrowser,
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          launchUrl(Uri.parse(text), mode: LaunchMode.externalApplication);
                        },
                        child: const Text('Open in browser'),
                      ),
                    ),
                  const SizedBox(width: 8),
                  withId(
                    Ids.textCopy,
                    FilledButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        Navigator.pop(context);
                      },
                      child: const Text('Copy'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Shows an error message with **OK**.
Future<void> showErrorSheet(BuildContext context, String message) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => withId(
      Ids.errorSheet,
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              withId(Ids.errorMessage, Text(message, style: Theme.of(context).textTheme.bodyLarge)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: withId(
                  Ids.errorOk,
                  FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Asks for a name to save a state under. Returns the name, or `null` when
/// cancelled. An empty name returns [defaultName].
Future<String?> showSaveSheet(BuildContext context, {required String defaultName}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _SaveSheet(defaultName: defaultName),
  );
}

class _SaveSheet extends StatefulWidget {
  const _SaveSheet({required this.defaultName});

  final String defaultName;

  @override
  State<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<_SaveSheet> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _name.text.trim();
    Navigator.pop(context, name.isEmpty ? widget.defaultName : name);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Save state', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            withId(
              Ids.saveName,
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: 'Name', hintText: widget.defaultName),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _confirm(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                withId(Ids.saveCancel, TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 8),
                withId(Ids.saveConfirm, FilledButton(onPressed: _confirm, child: const Text('Save'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
