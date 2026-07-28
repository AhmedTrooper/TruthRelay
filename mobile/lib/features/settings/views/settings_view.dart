import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/moderator_settings_repository.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final _json = TextEditingController();
  String? _msg;

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final raw = _json.text.trim();
      if (raw.isEmpty) {
        await ref.read(moderatorSettingsRepoProvider).clear();
        setState(() => _msg = 'Cleared.');
        return;
      }
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['name'] is! String ||
          m['public_key_b64'] is! String ||
          m['secret_key_b64'] is! String ||
          m['id'] is! String ||
          m['created_at'] is! String) {
        throw 'JSON must include id, name, public_key_b64, secret_key_b64, created_at';
      }
      await ref.read(moderatorSettingsRepoProvider).save(StoredModerator(
            id: m['id'] as String,
            name: m['name'] as String,
            publicKeyB64: m['public_key_b64'] as String,
            secretKeyB64: m['secret_key_b64'] as String,
            createdAt: m['created_at'] as String,
          ));
      setState(() => _msg = 'Saved.');
    } catch (e) {
      setState(() => _msg = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.read(moderatorSettingsRepoProvider).load();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text('Moderator keypair (paste from `cargo run -- keygen` + the assigned id from the server)'),
            const SizedBox(height: 8),
            TextField(
              controller: _json,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{"id":"...","name":"...","public_key_b64":"...","secret_key_b64":"...","created_at":"..."}',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _save, child: const Text('Save')),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg!)),
            const Divider(height: 32),
            const Text('Currently stored', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (stored == null)
              const Text('(none)', style: TextStyle(color: Colors.grey))
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Name: ${stored.name}'),
                  Text('ID: ${stored.id}'),
                  Text('Public key: ${stored.publicKeyB64}'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}