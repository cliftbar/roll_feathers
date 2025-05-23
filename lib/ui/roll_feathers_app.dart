import 'package:flutter/material.dart';
import 'package:roll_feathers/repositories/app_repository.dart';
import 'package:roll_feathers/ui/main_screen.dart';
import 'package:roll_feathers/ui/main_screen_vm.dart';
import 'package:roll_feathers/ui/roll_feathers_vm.dart';

// Handles theming
// launches main screen
class RollFeatherApp extends StatefulWidget {

  final AppRepository appRepo;
  final RollFeathersViewModel viewModel;


  const RollFeatherApp({super.key, required this.appRepo, required this.viewModel});

  static Future<RollFeatherApp> create(AppRepository appRepo) async {
    var view = await RollFeathersViewModel.create(appRepo);
    var app = RollFeatherApp(appRepo: appRepo, viewModel: view,);

    return app;
  }

  @override
  State<RollFeatherApp> createState() => _RollFeatherAppState();
}

class _RollFeatherAppState extends State<RollFeatherApp> {
  late RollFeathersViewModel _rollFeathersViewModel;

  @override
  void initState() {
    super.initState();
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
          child: MainScreenWidget(viewModel: MainScreenViewModel(widget.appRepo))
      );
    }
}
