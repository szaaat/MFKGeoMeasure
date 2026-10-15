import re

with open('/Users/szamosiattila/Downloads/mfkrtk01_v0.2.1_INS_DIAG.ino', 'r') as f:
    content = f.read()

# Update Update.begin error handling to send OTA_ERROR:BEGIN
update_begin_pattern = r'if \(!Update\.begin\(\s*firmwareSize,\s*U_FLASH\s*\)\)\s*\{\s*Serial\.println\(\s*"ERROR: Update\.begin failed\."\s*\);\s*Update\.printError\(\s*Serial\s*\);\s*return;\s*\}'
new_update_begin = '''if (!Update.begin(
            firmwareSize,
            U_FLASH
        ))
    {
        Serial.println(
            "ERROR: Update.begin failed."
        );

        Update.printError(
            Serial
        );
        
        if (deviceConnected)
        {
            configCharacteristic->setValue(
                "OTA_ERROR:BEGIN"
            );
            configCharacteristic->notify();
        }

        return;
    }'''

content = re.sub(update_begin_pattern, new_update_begin, content)

with open('/Users/szamosiattila/Downloads/mfkrtk01_v0.2.1_INS_DIAG.ino', 'w') as f:
    f.write(content)
