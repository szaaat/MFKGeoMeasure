import re

with open('/Users/szamosiattila/Downloads/mfkrtk01_v0.2.1_INS_DIAG.ino', 'r') as f:
    content = f.read()

# Make sure OTA DATA debug prints size overflow correctly
# Actually, the user asked:
# OTA DATA
# Received: xxx / xxx
# This is currently done in handleFirmwareData? Let's check handleFirmwareData.
