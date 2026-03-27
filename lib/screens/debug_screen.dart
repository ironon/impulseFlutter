import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/debug_log_service.dart';
import '../theme/app_theme.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final _logService   = DebugLogService();
  final _scrollCtrl   = ScrollController();
  StreamSubscription<DebugLogEntry>? _sub;
  bool _autoScroll    = true;

  @override
  void initState() {
    super.initState();
    _sub = _logService.stream.listen((_) {
      if (mounted) {
        setState(() {});
        if (_autoScroll) _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clear() {
    _logService.clear();
    setState(() {});
  }

  void _copyAll() {
    final text = _logService.entries.map((e) {
      final t = '${e.timestamp.hour.toString().padLeft(2, '0')}:'
                '${e.timestamp.minute.toString().padLeft(2, '0')}:'
                '${e.timestamp.second.toString().padLeft(2, '0')}.'
                '${e.timestamp.millisecond.toString().padLeft(3, '0')}';
      return '[$t] [${e.source}] ${e.decoded}\n  HEX: ${e.hex}';
    }).join('\n\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _logService.entries;

    return Scaffold(
      appBar: AppBar(
        title: Text('Debug  (${entries.length})'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.vertical_align_bottom,
              color: _autoScroll ? AppTheme.lightOrange : AppTheme.textGrey,
            ),
            tooltip: 'Auto-scroll',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: entries.isEmpty ? null : _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: entries.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Text(
                'No packets yet.\nConnect to the watch to see data.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
              ),
            )
          : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(8),
              itemCount: entries.length,
              itemBuilder: (context, i) => _EntryTile(entry: entries[i]),
            ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final DebugLogEntry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = entry.timestamp;
    final timeStr =
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.cardGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  color: AppTheme.textGrey,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.lightOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.source,
                  style: const TextStyle(
                    color: AppTheme.lightOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.decoded,
            style: const TextStyle(
              color: AppTheme.textWhite,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.hex,
            style: const TextStyle(
              color: AppTheme.textGrey,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
