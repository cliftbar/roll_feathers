import 'package:flutter/material.dart';

import 'package:roll_feathers/domains/webhook/payload_template.dart';
import 'package:roll_feathers/ui/webhook/webhook_payload_editor_vm.dart';

/// Payload editor: name + advanced options (method/format/content-type/headers),
/// a monospace body editor with a click-to-insert variable palette, and a live
/// preview (rendered against the canned sample) with inline validation.
class WebhookPayloadEditorScreen extends StatefulWidget {
  const WebhookPayloadEditorScreen({super.key, required this.vm});

  final WebhookPayloadEditorViewModel vm;

  @override
  State<WebhookPayloadEditorScreen> createState() => _WebhookPayloadEditorScreenState();
}

class _WebhookPayloadEditorScreenState extends State<WebhookPayloadEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _body;

  WebhookPayloadEditorViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: vm.name);
    _body = TextEditingController(text: vm.body);
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

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
    return Scaffold(
      appBar: AppBar(
        title: Text(readOnly ? '${vm.name} (built-in)' : 'Edit payload'),
        actions: [
          if (!readOnly)
            ListenableBuilder(
              listenable: vm,
              builder: (context, _) => TextButton(
                onPressed: vm.canSave
                    ? () async {
                        await vm.save.execute();
                        if (context.mounted) Navigator.pop(context, true);
                      }
                    : null,
                child: const Text('Save'),
              ),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => ListView(
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
              controller: _name,
              enabled: !readOnly,
              decoration: InputDecoration(labelText: 'Name', errorText: vm.nameError),
              onChanged: vm.setName,
            ),
            const SizedBox(height: 12),
            _advanced(readOnly),
            const SizedBox(height: 12),
            Text('Body', style: Theme.of(context).textTheme.titleSmall),
            TextField(
              controller: _body,
              enabled: !readOnly,
              maxLines: 10,
              minLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: vm.setBody,
            ),
            if (!readOnly) ...[
              const SizedBox(height: 8),
              _palette(),
            ],
            const SizedBox(height: 16),
            _preview(context),
          ],
        ),
      ),
    );
  }

  Widget _advanced(bool readOnly) => ExpansionTile(
        title: const Text('Advanced'),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
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
          const SizedBox(height: 8),
          Text('Content-Type: ${vm.build().effectiveContentType}',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      );

  Widget _labeled(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          child,
        ],
      );

  Widget _palette() => Wrap(
        spacing: 6,
        runSpacing: -6,
        children: [
          for (final entry in vm.variablePalette.entries)
            for (final token in entry.value)
              ActionChip(
                label: Text(token, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                onPressed: () => _insert(token),
              ),
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
            Text('Preview (sample roll)', style: Theme.of(context).textTheme.titleSmall),
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
