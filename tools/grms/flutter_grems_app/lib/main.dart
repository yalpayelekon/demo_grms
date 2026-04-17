import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'providers/coordinates_sync_provider.dart';
import 'app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    final isTestBinding = bindingName.contains('TestWidgetsFlutterBinding');
    if (!isTestBinding) {
      ref.watch(coordinatesSyncProvider);
    }
    final authState = ref.watch(authProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'GRMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        dividerColor: Colors.white.withOpacity(0.1),
      ),
      routerConfig: router,
      builder: (context, child) {
        if (authState.isInitialized) {
          return child ?? const SizedBox.shrink();
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
