import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/store.dart';
import 'core/storage/json_storage.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final store = await AppStore.load(JsonFileStorage(dir.path));
  runApp(NotebaseApp(store: store));
}
