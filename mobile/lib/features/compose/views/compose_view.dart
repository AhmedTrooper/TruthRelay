import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../requests/models/help_request.dart';
import '../../sync/models/outbox_entry.dart';

class ComposeView extends ConsumerStatefulWidget {
  const ComposeView({super.key});

  @override
  ConsumerState<ComposeView> createState() => _ComposeViewState();
}

class _ComposeViewState extends ConsumerState<ComposeView> {
  String _kind = 'Blood';
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _location = TextEditingController();
  final _contact = TextEditingController();
  bool _saving = false;

  static const _kinds = ['Blood', 'Missing', 'Supply'];

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _location.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final id = const Uuid().v4();
      final now = DateTime.now().toUtc().toIso8601String();
      final req = HelpRequest(
        id: id,
        kind: _kind,
        title: _title.text.trim(),
        body: _body.text.trim(),
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        contact: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
        status: 'Active',
        createdAt: now,
        receivedAt: now,
      );

      await ref.read(requestRepoProvider).insert(req);
      await ref.read(outboxRepoProvider).enqueue(
            kind: OutboxKind.request,
            payload: jsonEncode(req.toJson()),
          );

      if (!mounted) return;
      ref.invalidate(pendingOutboxCountProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved locally. Will sync when online.')),
      );
      context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('New Help Request')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Kind'),
              items: _kinds.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
              onChanged: (v) => setState(() => _kind = v ?? 'Blood'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              decoration: const InputDecoration(labelText: 'Body'),
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Location (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contact,
              decoration: const InputDecoration(labelText: 'Contact (optional)'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: canSubmit && !_saving ? _submit : null,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}