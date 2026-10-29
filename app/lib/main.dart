import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'domain/formats/block_catalog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Block-id catalog + mapping tables first: importers depend on it.
  await BlockCatalog.load();

  final boot = await AppBootstrap.init();

  runApp(ProviderScope(
    overrides: boot.overrides,
    child: S3dAppProxy(boot: boot),
  ));
}

/// Rebuilds the MaterialApp when the persisted language override changes.
class S3dAppProxy extends StatefulWidget {
  const S3dAppProxy({super.key, required this.boot});
  final AppBootstrap boot;

  @override
  State<S3dAppProxy> createState() => _S3dAppProxyState();
}

class _S3dAppProxyState extends State<S3dAppProxy> {
  @override
  void initState() {
    super.initState();
    widget.boot.settings.addListener(_onSettings);
  }

  void _onSettings() => setState(() {});

  @override
  void dispose() {
    widget.boot.settings.removeListener(_onSettings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      S3dApp(languageOverride: widget.boot.settings.languageOverride);
}
