import 'package:flutter/material.dart';

import 'package:roll_feathers/domains/webhook/payload_template.dart';
import 'package:roll_feathers/ui/webhook/webhook_payload_editor_vm.dart';

/// Payload editor: name + advanced options (method/format/content-type/headers),
/// a monospace body editor with a click-to-insert variable palette, and a live
/// preview (rendered against the canned sample) with inline validation.
///
/// Responsive: on a wide surface (web/desktop) the editor and the live preview
/// sit side by side so the preview stays visible while you edit. On a narrow
/// surface (phone) they split into `Edit` / `Preview` tabs, which keeps the body
/// and the variable palette together on the first screen (the chip you tap lands
/// right by the body) instead of one long scroll.
class WebhookPayloadEditorScreen extends StatefulWidget {
  const WebhookPayloadEditorScreen({super.key, required this.vm});

  final WebhookPayloadEditorViewModel vm;

  @override
  State<WebhookPayloadEditorScreen> createState() => _WebhookPayloadEditorScreenState();
}

/// Below this width we switch from side-by-side to tabbed. 900 keeps each pane
/// comfortably wide when split; phones/small windows fall back to tabs.
const double _kWideBreakpoint = 900;

class _WebhookPayloadEditorScreenState extends State<WebhookPayloadEditorScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _name;
  late final TextEditingController _body;
  late final TextEditingController _contentType;

  /// Owned here (not a DefaultTabController) so the selected tab survives the
  /// frequent rebuilds driven by the VM's live-preview notifications.
  late final TabController _tabs;

  WebhookPayloadEditorViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: vm.name);
    _body = TextEditingController(text: vm.body);
    _contentType = TextEditingController(text: vm.contentType ?? '');
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    _contentType.dispose();
    _tabs.dispose();
    super.dispose();
  }

  /// Confirms discarding unsaved edits before leaving the editor.
  Future<bool> _confirmDiscard(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('You have unsaved edits to this payload.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
          ],
        ),
      ) ??
      false;

  void _insert(String token) {
    final sel = _body.selection;
    final text = _body.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final snippet = token.replaceAll('…', '');
    final updated = text.replaceRange(start, end, snippet);
    _body.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + snippet.length),
    );
    vm.setBody(updated);
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = vm.isBuiltin;
    // Outer ListenableBuilder so PopScope.canPop tracks the dirty flag reactively.
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => PopScope(
        canPop: readOnly || !vm.dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmDiscard(context) && context.mounted) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(readOnly ? '${vm.name} (built-in)' : 'Edit payload'),
            actions: [
              if (!readOnly)
                TextButton(
                  onPressed: vm.canSave
                      ? () async {
                          await vm.save.execute();
                          if (context.mounted) Navigator.pop(context, true);
                        }
                      : null,
                  child: const Text('Save'),
                ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _kWideBreakpoint;
              return wide ? _wideLayout(context, readOnly) : _narrowLayout(context, readOnly);
            },
          ),
        ),
      ),
    );
  }

  /// Side-by-side: editor left, live preview + test-send right.
  Widget _wideLayout(BuildContext context, bool readOnly) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _editorPane(context, readOnly)),
          const VerticalDivider(width: 1),
          Expanded(child: _previewPane(context)),
        ],
      );

  /// Tabbed: keeps the body + palette on the first screen; preview one tap away
  /// (with an error badge so breakage is visible without switching).
  Widget _narrowLayout(BuildContext context, bool readOnly) => Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabs,
              tabs: [
                const Tab(text: 'Edit'),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Preview'),
                      if (!vm.preview.ok) ...[
                        const SizedBox(width: 6),
                        Semantics(
                          label: 'Preview has an error',
                          child: Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _editorPane(context, readOnly),
                _previewPane(context),
              ],
            ),
          ),
        ],
      );

  Widget _editorPane(BuildContext context, bool readOnly) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (readOnly)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('This is a built-in payload. Duplicate it to make an editable copy.'),
              ),
            ),
          TextField(
            key: const Key('payload-name-field'),
            controller: _name,
            enabled: !readOnly,
            decoration: InputDecoration(labelText: 'Name', errorText: vm.nameError),
            onChanged: vm.setName,
          ),
          const SizedBox(height: 12),
          _advanced(readOnly),
          const SizedBox(height: 12),
          Text('Body', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          TextField(
            controller: _body,
            enabled: !readOnly,
            minLines: 8,
            maxLines: null,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: vm.setBody,
          ),
          if (!readOnly) ...[
            const SizedBox(height: 12),
            _palette(context),
          ],
        ],
      );

  Widget _previewPane(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _preview(context),
          const SizedBox(height: 16),
          _testSend(context),
        ],
      );

  Widget _testSend(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          title: const Text('Test send'),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Fires the rendered sample payload to a URL right now (ignores the global '
                'webhooks toggle). Handy for catching CORS / endpoint errors while editing.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'URL', isDense: true),
                    onChanged: vm.setTestUrl,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => vm.testSend.execute(),
                  child: const Text('Send'),
                ),
              ],
            ),
            if (vm.testResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(vm.testResult!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ),
          ],
        ),
      );

  Widget _advanced(bool readOnly) => Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          title: const Text('Advanced'),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            Row(
              children: [
                Expanded(
                  child: _labeled(
                    'Method',
                    DropdownButton<String>(
                      isExpanded: true,
                      value: vm.method.toUpperCase(),
                      items: const [
                        DropdownMenuItem(value: 'POST', child: Text('POST')),
                        DropdownMenuItem(value: 'GET', child: Text('GET')),
                      ],
                      onChanged: readOnly ? null : (v) => vm.setMethod(v!),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _labeled(
                    'Format',
                    DropdownButton<PayloadFormat>(
                      isExpanded: true,
                      value: vm.format,
                      items: PayloadFormat.values
                          .map((f) => DropdownMenuItem(value: f, child: Text(f.name)))
                          .toList(),
                      onChanged: readOnly ? null : (v) => vm.setFormat(v!),
                    ),
                  ),
                ),
              ],
            ),
            if (vm.method.toUpperCase() == 'GET')
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('GET sends the body as a query string (form-encoded).',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentType,
              enabled: !readOnly,
              decoration: InputDecoration(
                labelText: 'Content-Type override',
                hintText: vm.format.defaultContentType,
                isDense: true,
              ),
              onChanged: vm.setContentType,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Effective: ${vm.effectiveContentType}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 12),
            _headersEditor(readOnly),
          ],
        ),
      );

  /// Custom request headers (e.g. `Authorization`). Chips with delete + an add
  /// dialog; the VM owns the map (persisted with the template).
  Widget _headersEditor(bool readOnly) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Headers', style: Theme.of(context).textTheme.labelMedium),
              if (!readOnly)
                TextButton.icon(
                  onPressed: () => _addHeader(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
            ],
          ),
          if (vm.headers.isEmpty)
            Text('None', style: Theme.of(context).textTheme.bodySmall)
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final e in vm.headers.entries)
                  InputChip(
                    label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 11)),
                    onDeleted: readOnly ? null : () => vm.removeHeader(e.key),
                  ),
              ],
            ),
        ],
      );

  Future<void> _addHeader(BuildContext context) async {
    final keyC = TextEditingController();
    final valC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add header'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: keyC, decoration: const InputDecoration(labelText: 'Name', hintText: 'Authorization')),
            TextField(controller: valC, decoration: const InputDecoration(labelText: 'Value')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && keyC.text.trim().isNotEmpty) vm.setHeader(keyC.text, valC.text);
    keyC.dispose();
    valC.dispose();
  }

  Widget _labeled(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          child,
        ],
      );

  /// Grouped, click-to-insert token palette. Grouping (vs a flat wrap) makes the
  /// two-dozen tokens scannable; it fits now that the preview no longer competes
  /// for vertical space beneath the body.
  Widget _palette(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Insert variable', style: Theme.of(context).textTheme.titleSmall),
          for (final entry in vm.variablePalette.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text(
                entry.key,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: -6,
              children: [
                for (final token in entry.value)
                  ActionChip(
                    label: Text(token, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    onPressed: () => _insert(token),
                  ),
              ],
            ),
          ],
        ],
      );

  Widget _preview(BuildContext context) {
    final p = vm.preview;
    return Card(
      color: p.ok ? null : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!p.ok) ...[
                  Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 6),
                ],
                Text(p.ok ? 'Preview (sample roll)' : 'Preview error',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              p.ok ? (p.output ?? '') : 'Error: ${p.error}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
