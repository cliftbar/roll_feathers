import 'package:flutter/material.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/ui/pixel_dice_screen.dart';
import 'package:roll_feathers/ui/roll_feathers_app_vm.dart';

// Main Application
class RollFeatherApp extends StatefulWidget {
  final RollFeathersAppVM viewModel;

  // Children
  final PixelDiceScreenWidget _mainScreenWidget;

  const RollFeatherApp._(this.viewModel, this._mainScreenWidget);

  static Future<RollFeatherApp> create(DiWrapper di) async {
    var view = await RollFeathersAppVM.create(di);

    var mainScreen = await PixelDiceScreenWidget.create(di);

    var app = RollFeatherApp._(view, mainScreen);

    return app;
  }

  @override
  State<RollFeatherApp> createState() => _RollFeatherAppState();
}

class _RollFeatherAppState extends State<RollFeatherApp> {
  late RollFeathersAppVM _rollFeathersViewModel;

  @override
  void initState() {
    super.initState();
    // Can I just use widget.viewModel directly??
    _rollFeathersViewModel = widget.viewModel;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _rollFeathersViewModel,
      builder: (context, child) {
        return MaterialApp(
          home: child,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: _rollFeathersViewModel.themeMode,
        );
      },
      child: widget._mainScreenWidget,
    );
  }
}
