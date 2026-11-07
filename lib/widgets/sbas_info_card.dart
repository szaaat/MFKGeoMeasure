import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/gnss_info_service.dart';
import '../models/gnss/sbas_status.dart';

class SbasInfoCard extends StatelessWidget {
  const SbasInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GnssInfoService>(
      builder: (context, gnssService, child) {
        final sbas = gnssService.sbasStatus;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.satellite_alt,
                      color: _getStateColor(sbas.state),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "SBAS / EGNOS Diagnosztika",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _buildStateBadge(sbas.state),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _getStateDescription(sbas.state),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                ),
                if (sbas.hasKnownEgnosPrn) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.stars, color: Colors.amber.shade900, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Európai EGNOS PRN azonosítva (123/126/136/138)",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (sbas.isActive && sbas.sbasSatellites.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 6),
                  Text(
                    "SBAS Műholdak (${sbas.sbasUsedInFixCount}/${sbas.sbasInViewCount} fixben):",
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: sbas.sbasSatellites.map((sat) {
                      final isUsed = sat.usedInFix == true;
                      return Chip(
                        avatar: Icon(
                          isUsed ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 16,
                          color: isUsed ? Colors.green.shade700 : Colors.grey,
                        ),
                        label: Text(
                          "PRN ${sat.svid ?? '?'}: ${sat.cn0DbHz?.toStringAsFixed(1) ?? '0'} dB-Hz",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isUsed ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        backgroundColor: isUsed ? Colors.green.shade50 : Colors.grey.shade100,
                        side: BorderSide(
                          color: isUsed ? Colors.green.shade300 : Colors.grey.shade300,
                        ),
                      );
                    }).toList(),
                  ),
                ],
                if (sbas.hasNavigationMessages) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.message_outlined, size: 14, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Text(
                        "SBAS navigációs keret vétele aktív${sbas.lastNavSvid != null ? ' (PRN ${sbas.lastNavSvid})' : ''}",
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  "Megjegyzés: Az Android keretrendszer nem ad közvetlen HAL visszajelzést a korrekció belső levonásáról.",
                  style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStateBadge(SbasState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getStateColor(state).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getStateColor(state)),
      ),
      child: Text(
        _getStateLabel(state),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _getStateColor(state),
        ),
      ),
    );
  }

  Color _getStateColor(SbasState state) {
    switch (state) {
      case SbasState.usedInFix:
        return Colors.green.shade700;
      case SbasState.detected:
        return Colors.blue.shade700;
      case SbasState.notDetected:
        return Colors.amber.shade800;
      case SbasState.unavailable:
        return Colors.grey;
    }
  }

  String _getStateLabel(SbasState state) {
    switch (state) {
      case SbasState.usedInFix:
        return "Fixben használva";
      case SbasState.detected:
        return "Észlelve";
      case SbasState.notDetected:
        return "Nem észlelhető";
      case SbasState.unavailable:
        return "Inaktív";
    }
  }

  String _getStateDescription(SbasState state) {
    switch (state) {
      case SbasState.usedInFix:
        return "Az Android GNSS vevő legalább egy SBAS műhold jeleit felhasználja a pozíciómeghatározáshoz.";
      case SbasState.detected:
        return "SBAS műholdak észlelhetők a látómezőben, de a GNSS vevő még nem vonta be őket a fixbe.";
      case SbasState.notDetected:
        return "A belső GNSS vevő aktív, de jelenleg nem észlelhető SBAS műhold a látómezőben.";
      case SbasState.unavailable:
        return "Az SBAS diagnosztika inaktív (iOS platform vagy külső RTK vevő használata esetén).";
    }
  }
}
