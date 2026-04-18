// TODO: streamline settings UI
import 'package:flutter/material.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';

import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/ui/app_settings/app_settings_screen_vm.dart';

/// A screen that displays and manages rule scripts.
class ScriptScreenWidget extends StatefulWidget {
  const ScriptScreenWidget({super.key, required this.viewModel});

  @override
  State<ScriptScreenWidget> createState() => _ScriptScreenWidgetState();

  final AppSettingsScreenViewModel viewModel;

}

class _ScriptScreenWidgetState extends State<ScriptScreenWidget> {
  String? _lastShownError;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
  }

  void _onViewModelChanged() {
    final err = widget.viewModel.saveError;
    if (err == null) {
      _lastShownError = null;
      return;
    }
    if (err == _lastShownError || !mounted) return;
    _lastShownError = err;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $err')),
        );
      }
    });
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rule Scripts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Saved Scripts', style: Theme.of(context).textTheme.titleLarge),
                ElevatedButton.icon(
                  onPressed: () => _showAddScriptDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New Script'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.viewModel,
              builder: (context, _) {
                final List<RuleScript> scripts = widget.viewModel.getRuleScripts();
                return scripts.isEmpty
                    ? const Center(child: Text('No scripts added'))
                    : ReorderableListView.builder(
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom),
                        itemCount: scripts.length,
                        onReorder: (oldIndex, newIndex) {
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          widget.viewModel.reorderRules(oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final isUserRule =
                              widget.viewModel.isUserOnlyRule(scripts[index].name);
                          return ListTile(
                            key: Key('script_$index'),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isUserRule)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(Icons.person, size: 16),
                                  ),
                                Checkbox(
                                  value: scripts[index].enabled,
                                  onChanged: (bool? value) {
                                    widget.viewModel.toggleRuleScript(
                                        scripts[index].name, value ?? false);
                                  },
                                ),
                              ],
                            ),
                            title: Text(scripts[index].displayName),
                            subtitle: Text(scripts[index].script,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () =>
                                      _showEditScriptDialog(context, index, scripts),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () {
                                    widget.viewModel.removeRule(index);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      );
              },
            ),
          ),
          ListenableBuilder(
            listenable: widget.viewModel,
            builder: (context, _) {
              final hidden = widget.viewModel.getHiddenDefaultRules();
              if (hidden.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      '${hidden.length} hidden rule${hidden.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  ...hidden.map((rule) => ListTile(
                        title: Text(rule.displayName),
                        trailing: TextButton(
                          onPressed: () => widget.viewModel.unhideRule(rule.name),
                          child: const Text('Restore'),
                        ),
                      )),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddScriptDialog(BuildContext context) {
    final TextEditingController contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        String? dialogError;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Script'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    TextField(
                      controller: contentController,
                      decoration: InputDecoration(
                        labelText: 'Script Content',
                        hintText: 'Enter your script here',
                        errorText: dialogError,
                      ),
                      maxLines: 10,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                TextButton(
                  child: const Text('Save'),
                  onPressed: () async {
                    if (contentController.text.isNotEmpty) {
                      await widget.viewModel.addRuleScript(contentController.text);
                      final err = widget.viewModel.saveError;
                      if (err != null) {
                        setDialogState(() => dialogError = err);
                      } else {
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditScriptDialog(
      BuildContext context, int index, List<RuleScript> scripts) {
    final TextEditingController contentController =
        TextEditingController(text: scripts[index].script);

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        String? dialogError;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Script'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    TextField(
                      controller: contentController,
                      decoration: InputDecoration(
                        labelText: 'Script Content',
                        hintText: 'Enter your script here',
                        errorText: dialogError,
                      ),
                      maxLines: 10,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                TextButton(
                  child: const Text('Save'),
                  onPressed: () async {
                    await widget.viewModel.addRuleScript(
                      contentController.text,
                      enabled: scripts[index].enabled,
                    );
                    final err = widget.viewModel.saveError;
                    if (err != null) {
                      setDialogState(() => dialogError = err);
                    } else {
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}
