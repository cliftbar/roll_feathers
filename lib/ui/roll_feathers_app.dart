import 'package:flutter/material.dart';
import 'package:roll_feathers/repositories/app_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_service.dart';
import 'package:roll_feathers/ui/main_screen.dart';
import 'package:roll_feathers/ui/roll_feathers_app_vm.dart';

// Main Application
class RollFeatherApp extends StatefulWidget {
  final AppRepository appRepo;
  final HaRepository haRepo;
  final RollFeathersAppVM viewModel;

  // Children
  final MainScreenWidget _mainScreenWidget;

  const RollFeatherApp._(this.appRepo, this.viewModel, this.haRepo, this._mainScreenWidget);

  static Future<RollFeatherApp> create(AppRepository appRepo) async {
    var haService = await HaService.create();
    var haRepo = HaRepository(HaConfigService(), haService);
    var view = await RollFeathersAppVM.create(appRepo);

    var mainScreen = await MainScreenWidget.create(appRepo, haRepo);

    var app = RollFeatherApp._(appRepo, view, haRepo, mainScreen);

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
