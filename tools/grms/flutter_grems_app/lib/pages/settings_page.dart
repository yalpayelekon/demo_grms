import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/lighting_device.dart';
import '../models/zones_models.dart';
import '../providers/auth_provider.dart';
import '../providers/coordinates_sync_provider.dart';
import '../providers/demo_rcu_settings_provider.dart';
import '../providers/lighting_devices_provider.dart';
import '../providers/preferences_provider.dart' as p;
import '../providers/room_service_settings_provider.dart' as s;
import '../providers/zones_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Profile'),
              Tab(text: 'Zones'),
              Tab(text: 'Room Services'),
              Tab(text: 'Preferences'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ProfileTab(),
            _ZonesTab(),
            _RoomServicesTab(),
            _PreferencesTab(),
          ],
        ),
      ),
    );
  }
}

class _ProfileTab extends ConsumerStatefulWidget {
  const _ProfileTab();

  @override
  ConsumerState<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<_ProfileTab> {
  final _currentDisplayNameController = TextEditingController();

  // Edit User State
  String? _selectedUsername;
  final _editDisplayNameController = TextEditingController();
  final _editPasswordController = TextEditingController();
  UserRole _editRole = UserRole.viewer;

  // New User State
  final _newUsernameController = TextEditingController();
  final _newDisplayNameController = TextEditingController();
  final _newPasswordController = TextEditingController();
  UserRole _newRole = UserRole.viewer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authProvider);
      _currentDisplayNameController.text = authState.user?.displayName ?? '';
      if (authState.users.isNotEmpty) {
        _onUserSelected(authState.users.first.username);
      }
    });
  }

  @override
  void dispose() {
    _currentDisplayNameController.dispose();
    _editDisplayNameController.dispose();
    _editPasswordController.dispose();
    _newUsernameController.dispose();
    _newDisplayNameController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  void _onUserSelected(String? username) {
    if (username == null) return;
    final authState = ref.read(authProvider);
    final user = authState.users.firstWhere(
      (u) => u.username == username,
      orElse: () => authState.users.first,
    );
    setState(() {
      _selectedUsername = username;
      _editDisplayNameController.text = user.displayName ?? '';
      _editPasswordController.clear();
      _editRole = user.role;
    });
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final isAdmin = user?.role == UserRole.admin;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard(
            title: 'User Information',
            child: Column(
              children: [
                _buildInfoRow('Username:', user?.username ?? 'N/A'),
                _buildInfoRow('Role:', user?.role.label.toUpperCase() ?? 'N/A'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _currentDisplayNameController,
                        decoration: const InputDecoration(
                          labelText: 'Display Name',
                          hintText: 'Enter display name',
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () async {
                        await ref
                            .read(authProvider.notifier)
                            .updateDisplayName(
                              _currentDisplayNameController.text,
                            );
                        _showInfo('Display name updated!');
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 24),
            _buildCard(
              title: 'User Management',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedUsername,
                    decoration: const InputDecoration(labelText: 'Select User'),
                    items: authState.users.map((u) {
                      return DropdownMenuItem(
                        value: u.username,
                        child: Text(u.username),
                      );
                    }).toList(),
                    onChanged: _onUserSelected,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _editDisplayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _editPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      hintText: 'Leave blank to keep existing',
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<UserRole>(
                    value: _editRole,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: UserRole.values.map((r) {
                      return DropdownMenuItem(
                        value: r,
                        child: Text(r.label.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _editRole = val!),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          if (_selectedUsername == null) return;
                          final res = await ref
                              .read(authProvider.notifier)
                              .updateUser(
                                _selectedUsername!,
                                _editPasswordController.text.isEmpty
                                    ? null
                                    : _editPasswordController.text,
                                _editRole,
                                _editDisplayNameController.text,
                              );
                          _showInfo(res.message);
                        },
                        child: const Text('Save User'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () async {
                          if (_selectedUsername == null) return;
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Confirm Delete'),
                              content: Text(
                                'Are you sure you want to delete ${_selectedUsername}?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            final res = await ref
                                .read(authProvider.notifier)
                                .deleteUser(_selectedUsername!);
                            _showInfo(res.message);
                            if (res.success && authState.users.isNotEmpty) {
                              _onUserSelected(authState.users.first.username);
                            }
                          }
                        },
                        child: const Text(
                          'Delete User',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 48),
                  const Text(
                    'Add New User',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _newUsernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _newDisplayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _newPasswordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<UserRole>(
                    value: _newRole,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: UserRole.values.map((r) {
                      return DropdownMenuItem(
                        value: r,
                        child: Text(r.label.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _newRole = val!),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      if (_newUsernameController.text.isEmpty ||
                          _newPasswordController.text.isEmpty) {
                        _showInfo('Username and Password are required');
                        return;
                      }
                      final res = await ref
                          .read(authProvider.notifier)
                          .addUser(
                            StoredUser(
                              username: _newUsernameController.text,
                              displayName: _newDisplayNameController.text,
                              password: _newPasswordController.text,
                              role: _newRole,
                            ),
                          );
                      _showInfo(res.message);
                      if (res.success) {
                        _newUsernameController.clear();
                        _newDisplayNameController.clear();
                        _newPasswordController.clear();
                        setState(() => _newRole = UserRole.viewer);
                        _onUserSelected(authState.users.last.username);
                      }
                    },
                    child: const Text('Create User'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

enum _ZonesSubTab { buttons, lightingDevices }

class _ZonesTab extends ConsumerStatefulWidget {
  const _ZonesTab();

  @override
  ConsumerState<_ZonesTab> createState() => _ZonesTabState();
}

class _ZonesTabState extends ConsumerState<_ZonesTab> {
  _ZonesSubTab _subTab = _ZonesSubTab.buttons;

  void _showInfo(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showZoneEditor({ZoneButton? existing, int? index}) async {
    final nameController = TextEditingController(
      text: existing?.uiDisplayName ?? '',
    );
    final idController = TextEditingController(
      text: existing?.buttonName ?? '',
    );
    final xController = TextEditingController(
      text: existing == null ? '' : existing.xCoordinate.toStringAsFixed(0),
    );
    final yController = TextEditingController(
      text: existing == null ? '' : existing.yCoordinate.toStringAsFixed(0),
    );
    var active = existing?.active ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(
              existing == null ? 'Add Zone Button' : 'Edit Zone Button',
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: idController,
                    decoration: const InputDecoration(labelText: 'Button ID'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: xController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'X Coordinate',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: yController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Y Coordinate',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: active,
                    title: const Text('Active'),
                    onChanged: (value) => setDialogState(() => active = value),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    if (saved != true) {
      return;
    }

    final name = nameController.text.trim();
    final id = idController.text.trim();
    final x = double.tryParse(xController.text.trim());
    final y = double.tryParse(yController.text.trim());

    if (name.isEmpty || id.isEmpty || x == null || y == null) {
      _showInfo('Display name, ID, and coordinates are required.');
      return;
    }

    final zone = ZoneButton(
      uiDisplayName: name,
      buttonName: id,
      xCoordinate: x,
      yCoordinate: y,
      active: active,
    );

    final notifier = ref.read(zonesProvider.notifier);
    if (index == null) {
      notifier.addZoneLayout(zone);
      _showInfo('Zone button added.');
    } else {
      notifier.updateZoneLayout(index, zone);
      _showInfo('Zone button updated.');
    }
  }

  Future<void> _showLightingEditor({
    LightingDeviceConfig? existing,
    int? index,
  }) async {
    final addressController = TextEditingController(
      text: existing?.address.toString() ?? '',
    );
    final nameController = TextEditingController(text: existing?.name ?? '');
    final xController = TextEditingController(
      text: existing == null ? '' : existing.x.toStringAsFixed(0),
    );
    final yController = TextEditingController(
      text: existing == null ? '' : existing.y.toStringAsFixed(0),
    );
    var type = existing?.type ?? LightingDeviceType.onboard;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Add Lighting Device' : 'Edit Lighting Device',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: addressController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<LightingDeviceType>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(
                      value: LightingDeviceType.onboard,
                      child: Text('Onboard'),
                    ),
                    DropdownMenuItem(
                      value: LightingDeviceType.dali,
                      child: Text('DALI'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => type = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: xController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'X Coordinate'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: yController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Y Coordinate'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      return;
    }

    final address = int.tryParse(addressController.text.trim());
    final name = nameController.text.trim();
    final x = double.tryParse(xController.text.trim());
    final y = double.tryParse(yController.text.trim());

    if (address == null || name.isEmpty || x == null || y == null) {
      _showInfo('Address, name, and coordinates are required.');
      return;
    }

    final config = LightingDeviceConfig(
      address: address,
      name: name,
      x: x,
      y: y,
      type: type,
    );

    final notifier = ref.read(lightingDevicesProvider.notifier);
    if (index == null) {
      notifier.addConfig(config);
      _showInfo('Lighting device added.');
    } else {
      notifier.updateConfig(index, config);
      _showInfo('Lighting device updated.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final zonesState = ref.watch(zonesProvider);
    ref.watch(lightingDevicesProvider);
    final lightingNotifier = ref.read(lightingDevicesProvider.notifier);
    final buttons = zonesState.zonesData.homePageBlockButtons;
    final configs = lightingNotifier.configs;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Buttons'),
                selected: _subTab == _ZonesSubTab.buttons,
                onSelected: (_) =>
                    setState(() => _subTab = _ZonesSubTab.buttons),
              ),
              ChoiceChip(
                label: const Text('Lighting Devices'),
                selected: _subTab == _ZonesSubTab.lightingDevices,
                onSelected: (_) =>
                    setState(() => _subTab = _ZonesSubTab.lightingDevices),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_subTab == _ZonesSubTab.buttons)
            _buildCard(
              title: 'Zone Buttons Configuration',
              child: Column(
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _showZoneEditor(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Zone'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Reset Zones'),
                              content: const Text(
                                'Reset all zone buttons to defaults?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            ref.read(zonesProvider.notifier).resetZoneLayouts();
                            _showInfo('Zone layouts reset.');
                          }
                        },
                        child: const Text('Reset Zones'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: buttons.length,
                    itemBuilder: (context, index) {
                      final btn = buttons[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(child: Text('#${index + 1}')),
                          title: Text(btn.uiDisplayName),
                          subtitle: Text(
                            'ID: ${btn.buttonName} | Pos: (${btn.xCoordinate.toStringAsFixed(0)}, ${btn.yCoordinate.toStringAsFixed(0)})',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: btn.active,
                                onChanged: (val) {
                                  ref
                                      .read(zonesProvider.notifier)
                                      .updateZoneLayout(
                                        index,
                                        btn.copyWith(active: val),
                                      );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _showZoneEditor(
                                  existing: btn,
                                  index: index,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Zone'),
                                      content: Text(
                                        'Delete zone "${btn.uiDisplayName}"?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    ref
                                        .read(zonesProvider.notifier)
                                        .deleteZoneLayout(index);
                                    _showInfo('Zone deleted.');
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            )
          else
            _buildCard(
              title: 'Lighting Devices Configuration',
              child: Column(
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _showLightingEditor(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Device'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Reset Lighting Devices'),
                              content: const Text(
                                'Reset all lighting devices to defaults?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await ref
                                .read(lightingDevicesProvider.notifier)
                                .resetConfigs();
                            _showInfo('Lighting devices reset.');
                          }
                        },
                        child: const Text('Reset Lighting Devices'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: configs.length,
                    itemBuilder: (context, index) {
                      final cfg = configs[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${cfg.address}')),
                          title: Text(cfg.name),
                          subtitle: Text(
                            'Type: ${cfg.type == LightingDeviceType.dali ? "DALI" : "Onboard"} | Pos: (${cfg.x.toStringAsFixed(0)}, ${cfg.y.toStringAsFixed(0)})',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _showLightingEditor(
                                  existing: cfg,
                                  index: index,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Device'),
                                      content: Text(
                                        'Delete device "${cfg.name}"?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    ref
                                        .read(lightingDevicesProvider.notifier)
                                        .deleteConfig(index);
                                    _showInfo('Lighting device deleted.');
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RoomServicesTab extends ConsumerStatefulWidget {
  const _RoomServicesTab();

  @override
  ConsumerState<_RoomServicesTab> createState() => _RoomServicesTabState();
}

class _RoomServicesTabState extends ConsumerState<_RoomServicesTab> {
  final _murController = TextEditingController();
  final _laundryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsState = ref.read(s.roomServiceSettingsProvider);
      _murController.text = settingsState.settings.murDelayThresholdSeconds
          .toString();
      _laundryController.text = settingsState
          .settings
          .laundryDelayThresholdSeconds
          .toString();
    });
  }

  @override
  void dispose() {
    _murController.dispose();
    _laundryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _buildCard(
        title: 'Room Service Thresholds',
        child: Column(
          children: [
            TextField(
              controller: _murController,
              decoration: const InputDecoration(
                labelText: 'MUR Delay Threshold (seconds)',
                helperText:
                    'Services exceeding this duration will be marked as delayed',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _laundryController,
              decoration: const InputDecoration(
                labelText: 'Laundry Service Threshold (seconds)',
                helperText:
                    'Laundry service exceeding this duration will be marked as finished',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    final mur = int.tryParse(_murController.text.trim());
                    final laundry = int.tryParse(
                      _laundryController.text.trim(),
                    );
                    if (mur == null ||
                        laundry == null ||
                        mur < 1 ||
                        laundry < 1) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Threshold values must be numeric and at least 1 second.',
                          ),
                        ),
                      );
                      return;
                    }

                    ref
                        .read(s.roomServiceSettingsProvider.notifier)
                        .updateSettings(
                          murDelayThresholdSeconds: mur,
                          laundryDelayThresholdSeconds: laundry,
                        );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Settings saved')),
                    );
                  },
                  child: const Text('Save Settings'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(s.roomServiceSettingsProvider.notifier)
                        .resetSettings();
                    final updatedSettings = ref
                        .read(s.roomServiceSettingsProvider)
                        .settings;
                    _murController.text = updatedSettings
                        .murDelayThresholdSeconds
                        .toString();
                    _laundryController.text = updatedSettings
                        .laundryDelayThresholdSeconds
                        .toString();
                  },
                  child: const Text('Reset to Default'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferencesTab extends ConsumerStatefulWidget {
  const _PreferencesTab();

  @override
  ConsumerState<_PreferencesTab> createState() => _PreferencesTabState();
}

class _PreferencesTabState extends ConsumerState<_PreferencesTab> {
  final _cityController = TextEditingController();
  final _demoRcuHostController = TextEditingController();
  final _demoRcuPortController = TextEditingController();
  bool _demoRcuInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefsState = ref.read(p.preferencesProvider);
      _cityController.text = prefsState.preferences.city;
    });
  }

  @override
  void dispose() {
    _cityController.dispose();
    _demoRcuHostController.dispose();
    _demoRcuPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefsState = ref.watch(p.preferencesProvider);
    final prefs = prefsState.preferences;
    final authState = ref.watch(authProvider);
    final demoRcuSettingsState = ref.watch(demoRcuSettingsProvider);
    final effectiveSourceMode = ref.watch(
      effectiveLightingCoordinatesSourceModeProvider,
    );
    final sourceModeOverride = ref.watch(
      lightingCoordinatesSourceModeOverrideProvider,
    );
    final isAdmin = authState.role == UserRole.admin;

    demoRcuSettingsState.whenData((value) {
      if (_demoRcuInitialized) {
        return;
      }
      _demoRcuHostController.text = value.host;
      _demoRcuPortController.text = value.port.toString();
      _demoRcuInitialized = true;
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildCard(
            title: 'Date, Time & Weather Preferences',
            child: Column(
              children: [
                DropdownButtonFormField<p.DateFormat>(
                  value: prefs.dateFormat,
                  decoration: const InputDecoration(labelText: 'Date Format'),
                  items: p.DateFormat.values.map((f) {
                    return DropdownMenuItem(value: f, child: Text(f.label));
                  }).toList(),
                  onChanged: (val) => ref
                      .read(p.preferencesProvider.notifier)
                      .updatePreferences(dateFormat: val),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<p.TimeFormat>(
                  value: prefs.timeFormat,
                  decoration: const InputDecoration(labelText: 'Time Format'),
                  items: p.TimeFormat.values.map((f) {
                    return DropdownMenuItem(value: f, child: Text(f.label));
                  }).toList(),
                  onChanged: (val) => ref
                      .read(p.preferencesProvider.notifier)
                      .updatePreferences(timeFormat: val),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _cityController,
                  decoration: const InputDecoration(
                    labelText: 'City (for weather)',
                    helperText:
                        'City name used for weather information display',
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        ref
                            .read(p.preferencesProvider.notifier)
                            .updatePreferences(city: _cityController.text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Preferences saved')),
                        );
                      },
                      child: const Text('Save Preferences'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(p.preferencesProvider.notifier)
                            .resetPreferences();
                        _cityController.text = ref
                            .read(p.preferencesProvider)
                            .preferences
                            .city;
                      },
                      child: const Text('Reset to Default'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildCard(
            title: 'Demo RCU Connection',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Room: ${demoRcuSettingsState.valueOrNull?.room ?? "Demo 101"}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _demoRcuHostController,
                  enabled: isAdmin,
                  decoration: const InputDecoration(
                    labelText: 'RCU Host / IP',
                    helperText:
                        'Backend setting used by testcomm_go for Demo 101',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _demoRcuPortController,
                  enabled: isAdmin,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'RCU Port'),
                ),
                if (demoRcuSettingsState.isLoading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (demoRcuSettingsState.hasError) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load backend setting: ${demoRcuSettingsState.error}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: !isAdmin
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final host = _demoRcuHostController.text.trim();
                              final port = int.tryParse(
                                _demoRcuPortController.text.trim(),
                              );
                              if (host.isEmpty || port == null) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Host and numeric port are required.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              final error = await ref
                                  .read(demoRcuSettingsProvider.notifier)
                                  .save(host: host, port: port);
                              if (!context.mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    error == null
                                        ? 'Demo RCU settings saved'
                                        : error.message,
                                  ),
                                ),
                              );
                            },
                      child: const Text('Save Demo RCU'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () async {
                        _demoRcuInitialized = false;
                        await ref
                            .read(demoRcuSettingsProvider.notifier)
                            .reload();
                      },
                      child: const Text('Reload'),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final defaultHost = resolveDemoRcuDefaultHost();
                          const defaultPort = 5556;
                          _demoRcuHostController.text = defaultHost;
                          _demoRcuPortController.text = '$defaultPort';
                          final error = await ref
                              .read(demoRcuSettingsProvider.notifier)
                              .save(host: defaultHost, port: defaultPort);
                          if (!context.mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                error == null
                                    ? 'Demo RCU reset to defaults'
                                    : error.message,
                              ),
                            ),
                          );
                        },
                        child: const Text('Reset to Default'),
                      ),
                    ],
                  ],
                ),
                if (!isAdmin) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Only admins can change the backend RCU endpoint.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 16),
            _buildCard(
              title: 'Debug: Lighting Coordinate Source',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Runtime source mode: ${_sourceModeLabel(effectiveSourceMode)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Session-only override. Not persisted and no backend write is performed.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Asset in Debug'),
                        selected:
                            effectiveSourceMode ==
                            LightingCoordinatesSourceMode
                                .assetInDebugBackendInRelease,
                        onSelected: (_) {
                          ref
                              .read(
                                lightingCoordinatesSourceModeOverrideProvider
                                    .notifier,
                              )
                              .state = LightingCoordinatesSourceMode
                              .assetInDebugBackendInRelease;
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Backend Always'),
                        selected:
                            effectiveSourceMode ==
                            LightingCoordinatesSourceMode.backendAlways,
                        onSelected: (_) {
                          ref
                              .read(
                                lightingCoordinatesSourceModeOverrideProvider
                                    .notifier,
                              )
                              .state = LightingCoordinatesSourceMode
                              .backendAlways;
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Asset Always'),
                        selected:
                            effectiveSourceMode ==
                            LightingCoordinatesSourceMode.assetAlways,
                        onSelected: (_) {
                          ref
                              .read(
                                lightingCoordinatesSourceModeOverrideProvider
                                    .notifier,
                              )
                              .state = LightingCoordinatesSourceMode
                              .assetAlways;
                        },
                      ),
                    ],
                  ),
                  if (sourceModeOverride != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        ref
                                .read(
                                  lightingCoordinatesSourceModeOverrideProvider
                                      .notifier,
                                )
                                .state =
                            null;
                      },
                      child: const Text('Clear override (use app default)'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _sourceModeLabel(LightingCoordinatesSourceMode mode) {
    switch (mode) {
      case LightingCoordinatesSourceMode.assetInDebugBackendInRelease:
        return 'Asset in Debug, Backend in Release';
      case LightingCoordinatesSourceMode.backendAlways:
        return 'Backend Always';
      case LightingCoordinatesSourceMode.assetAlways:
        return 'Asset Always';
    }
  }
}

Widget _buildCard({required String title, required Widget child}) {
  return Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.blue.withOpacity(0.1),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ],
    ),
  );
}
