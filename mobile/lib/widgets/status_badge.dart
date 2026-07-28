import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String kind;
  final bool verified;
  const StatusBadge({super.key, required this.kind, this.verified = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = _spec();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  (Color, Color, String) _spec() {
    if (verified) return (const Color(0xFF065f46), const Color(0xFF6ee7b7), 'VERIFIED');
    switch (kind) {
      case 'VerifiedUpdate':
        return (const Color(0xFF0c4a6e), const Color(0xFF7dd3fc), 'VERIFIED UPDATE');
      case 'Debunk':
        return (const Color(0xFF881337), const Color(0xFFfda4af), 'DEBUNKED');
      case 'Missing':
        return (const Color(0xFF7c2d12), const Color(0xFFfcd34d), 'MISSING');
      case 'Blood':
        return (const Color(0xFF881337), const Color(0xFFfda4af), 'BLOOD');
      case 'Supply':
        return (const Color(0xFF4c1d95), const Color(0xFFc4b5fd), 'SUPPLY');
      default:
        return (const Color(0xFF1e293b), const Color(0xFFcbd5e1), kind.toUpperCase());
    }
  }
}