import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';

class LocationDisclosureService {
  static const String prefKey = 'location_prominent_disclosure_accepted';

  static Future<bool?> checkAndShowDisclosure(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(prefKey)) {
      return prefs.getBool(prefKey);
    }

    if (!context.mounted) return null;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prominent disclosure requires explicit user action
      builder: (dialogContext) => const LocationProminentDisclosureDialog(),
    );

    if (accepted != null) {
      await prefs.setBool(prefKey, accepted);
    }
    return accepted;
  }
}

class LocationProminentDisclosureDialog extends StatelessWidget {
  const LocationProminentDisclosureDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      title: Row(
        children: [
          Icon(Icons.location_on, color: Colors.blue[800], size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.locationDisclosureTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.blue.shade800, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.locationDisclosureHighlight,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.locationDisclosureBody,
              style: const TextStyle(fontSize: 13, height: 1.45, color: Colors.black87),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            l10n.locationDisclosureDecline,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[800],
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            l10n.locationDisclosureAccept,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
