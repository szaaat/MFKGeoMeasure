import re

with open('lib/screens/mfkrtk_ota_screen.dart', 'r') as f:
    content = f.read()

# Update get_state_color
old_color = '''      case OtaUpdateState.uploading: return Colors.blue;
      default: return Colors.black;'''

new_color = '''      case OtaUpdateState.uploading: return Colors.blue;
      case OtaUpdateState.verifyingVersion: return Colors.orange;
      default: return Colors.black;'''
content = content.replace(old_color, new_color)

# Add reported firmware info row
old_info = '''                    _infoRow('File Size:', '${_otaService.firmwareSize} bytes'),
                    _infoRow('SHA-256:', _otaService.sha256Hash ?? '-'),'''

new_info = '''                    _infoRow('Target Firmware:', _otaService.firmwareVersion ?? '-'),
                    _infoRow('Reported Firmware:', _otaService.reportedFirmwareVersion ?? '-'),
                    if (_otaService.state == OtaUpdateState.completed)
                      _infoRow('Verification:', 'PASS', color: Colors.green)
                    else if (_otaService.state == OtaUpdateState.failed && _otaService.errorMessage == 'VERSION MISMATCH')
                      _infoRow('Verification:', 'FAILED', color: Colors.red),
                    const SizedBox(height: 8),
                    _infoRow('File Size:', '${_otaService.firmwareSize} bytes'),
                    _infoRow('SHA-256:', _otaService.sha256Hash ?? '-'),'''
content = content.replace(old_info, new_info)

with open('lib/screens/mfkrtk_ota_screen.dart', 'w') as f:
    f.write(content)
