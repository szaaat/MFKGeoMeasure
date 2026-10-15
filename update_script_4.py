import re

with open('/Users/szamosiattila/Downloads/mfkrtk01_v0.2.1_INS_DIAG.ino', 'r') as f:
    content = f.read()

# Make sure we print "Received: xxx / xxx"
receive_pattern = r'otaReceivedSize \+=[\s\S]*?dataSize;\s*// --------------------------------------------------------------------\s*// Progress\s*// --------------------------------------------------------------------'

new_receive = '''otaReceivedSize +=
        dataSize;

    Serial.println("OTA DATA");
    Serial.print("Received: ");
    Serial.print(otaReceivedSize);
    Serial.print(" / ");
    Serial.println(otaExpectedSize);

    // --------------------------------------------------------------------
    // Progress
    // --------------------------------------------------------------------'''

content = re.sub(receive_pattern, new_receive, content)

with open('/Users/szamosiattila/Downloads/mfkrtk01_v0.2.1_INS_DIAG.ino', 'w') as f:
    f.write(content)

