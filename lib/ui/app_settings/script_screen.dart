import 'package:flutter/material.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';

import '../../di/di.dart';
import 'app_settings_screen_vm.dart';

/// A screen that displays and manages rule scripts.
class ScriptScreenWidget extends StatefulWidget {
  const ScriptScreenWidget({super.key, required this.viewModel});

  @override
  State<ScriptScreenWidget> createState() => _ScriptScreenWidgetState();

  final AppSettingsScreenViewModel viewModel;

  static Future<ScriptScreenWidget> create(DiWrapper di) async {
    var vm = AppSettingsScreenViewModel(di);
    var widget = ScriptScreenWidget(viewModel: vm);

    return widget;
  }
}

class _ScriptScreenWidgetState extends State<ScriptScreenWidget> {
  // This is just a placeholder list for UI demonstration
  // In a real implementation, this would be fetched from a data source
  // List<Map<String, dynamic>> scripts = [
  //   {'name': 'Example Script 1', 'content': 'Script content goes here...', 'selected': false},
  //   {'name': 'Example Script 2', 'content': 'Another script content...', 'selected': false},
  //   {'name': 'Example Script 3', 'content': 'Yet another script content...', 'selected': false},
  // ];

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
                List<RuleScript> scripts = widget.viewModel.getRuleScripts();
                return scripts.isEmpty
                    ? const Center(child: Text('No scripts added'))
                    : ReorderableListView.builder(
                      itemCount: scripts.length,
                      onReorder: (oldIndex, newIndex) {
                        if (oldIndex < newIndex) {
                          newIndex -= 1;
                        }
                        widget.viewModel.reorderRules(oldIndex, newIndex);
                        // setState(() {
                        //   if (oldIndex < newIndex) {
                        //     newIndex -= 1;
                        //   }
                        //
                        // });
                      },
                      itemBuilder: (context, index) {
                        return ListTile(
                          key: Key('script_$index'),
                          leading: Checkbox(
                            value: scripts[index].enabled,
                            onChanged: (bool? value) {
                              widget.viewModel.toggleRuleScript(scripts[index].name, value ?? false);
                              // setState(() {
                              //
                              //   // scripts[index].enabled = value ?? false;
                              // });
                            },
                          ),
                          title: Text(scripts[index].name),
                          subtitle: Text(scripts[index].script, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _showEditScriptDialog(context, index, scripts),
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
        ],
      ),
    );
  }

  void _showAddScriptDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add New Script'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Script Name', hintText: 'Enter a name for your script'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contentController,
                  decoration: const InputDecoration(labelText: 'Script Content', hintText: 'Enter your script here'),
                  maxLines: 10,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  setState(() {
                    widget.viewModel.addRuleScript(contentController.text);
                  });
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showEditScriptDialog(BuildContext context, int index, List<RuleScript> scripts) {
    // Get the current script values
    scripts[index].name;
    String currentContent = scripts[index].script;

    // Create controllers with the current values
    // final TextEditingController nameController = TextEditingController(text: currentName);
    final TextEditingController contentController = TextEditingController(text: currentContent);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Script'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                TextField(
                  controller: contentController,
                  decoration: const InputDecoration(labelText: 'Script Content', hintText: 'Enter your script here'),
                  maxLines: 10,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                widget.viewModel.addRuleScript(contentController.text, enabled: scripts[index].enabled);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
