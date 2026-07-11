import 'package:flutter/material.dart';

import 'package:roll_feathers/domains/webhook/payload_template.dart';
import 'package:roll_feathers/domains/webhook/webhook_payload_domain.dart';
import 'package:roll_feathers/ui/webhook/webhook_payload_editor_screen.dart';
import 'package:roll_feathers/ui/webhook/webhook_payload_editor_vm.dart';
import 'package:roll_feathers/ui/webhook/webhook_payloads_screen_vm.dart';

/// Library screen for webhook payloads: built-in templates + your payloads, with
/// new / duplicate / edit / delete. Referenced from a rule via
/// `webhook <url> with <name>`.
class WebhookPayloadsScreen extends StatelessWidget {
  const WebhookPayloadsScreen({super.key, required this.vm, required this.domain});

  final WebhookPayloadsScreenViewModel vm;
  final WebhookPayloadDomain domain;

  Future<void> _openEditor(BuildContext context, PayloadTemplate t) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WebhookPayloadEditorScreen(vm: WebhookPayloadEditorViewModel(domain, t)),
      ),
    );
    if (result == true) vm.load.execute();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Webhook Payloads')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, vm.newBlank()),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (vm.loading) return const Center(child: CircularProgressIndicator());
          return ListView(
            children: [
              _sectionHeader(context, 'Built-in'),
              for (final p in vm.builtins)
                ListTile(
                  leading: const Icon(Icons.lock_outline, semanticLabel: 'Built-in (read-only)'),
                  title: Text(p.name),
                  subtitle: Text('${p.method} · ${p.format.name} · use with `${p.id}`'),
                  trailing: IconButton(
                    tooltip: 'Duplicate',
                    icon: const Icon(Icons.copy),
                    onPressed: () => _openEditor(context, vm.duplicate(p)),
                  ),
                  onTap: () => _openEditor(context, p),
                ),
              _sectionHeader(context, 'Your payloads'),
              if (vm.userPayloads.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No custom payloads yet. Tap New, or duplicate a built-in to start.'),
                ),
              for (final p in vm.userPayloads)
                ListTile(
                  leading: const Icon(Icons.webhook),
                  title: Text(p.name),
                  subtitle: Text('${p.method} · ${p.format.name}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Duplicate',
                        icon: const Icon(Icons.copy),
                        onPressed: () => _openEditor(context, vm.duplicate(p)),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, p),
                      ),
                    ],
                  ),
                  onTap: () => _openEditor(context, p),
                ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Future<void> _confirmDelete(BuildContext context, PayloadTemplate p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text('Rules referencing it by name will fall back to skipping that webhook.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) vm.deletePayload.execute(p);
  }
}
