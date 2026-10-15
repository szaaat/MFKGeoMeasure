import re

with open('/Users/szamosiattila/Downloads/mfkrtk01_v0.2.1_INS_DIAG.ino', 'r') as f:
    content = f.read()

# Update FirmwareUpdateCallbacks
callback_pattern = r'class FirmwareUpdateCallbacks : public BLECharacteristicCallbacks\s*\{\s*void onWrite\(BLECharacteristic\*\s*characteristic\)\s*\{\s*String data =\s*characteristic->getValue\(\);\s*if \(data\.length\(\) == 0\)\s*return;\s*handleFirmwareData\(data\);\s*\}\s*\};'
new_callback = '''class FirmwareUpdateCallbacks : public BLECharacteristicCallbacks
{
    void onWrite(BLECharacteristic* characteristic)
    {
        uint8_t* data = characteristic->getData();
        size_t len = characteristic->getLength();

        if (len == 0 || data == nullptr)
            return;

        handleFirmwareData(data, len);
    }
};'''
content = re.sub(callback_pattern, new_callback, content)

# Update handleFirmwareData signature and body
handle_pattern = r'void handleFirmwareData\(String data\)\s*\{\s*if \(!otaInProgress\)\s*\{\s*Serial\.println\(\s*"ERROR: Firmware data without OTA\."\s*\);\s*return;\s*\}\s*size_t dataSize =\s*data\.length\(\);'
new_handle = '''void handleFirmwareData(const uint8_t* data, size_t len)
{
    if (!otaInProgress)
    {
        Serial.println(
            "ERROR: Firmware data without OTA."
        );

        return;
    }

    size_t dataSize = len;'''
content = re.sub(handle_pattern, new_handle, content)

# Update Update.write
update_write_pattern = r'size_t written =\s*Update\.write\(\s*\(uint8_t\*\)data\.c_str\(\),\s*dataSize\s*\);'
new_update_write = '''size_t written =
        Update.write(
            (uint8_t*)data,
            dataSize
        );'''
content = re.sub(update_write_pattern, new_update_write, content)

# Update mbedtls_sha256_update
sha256_update_pattern = r'mbedtls_sha256_update\(\s*&sha256Context,\s*\(const unsigned char\*\)\s*data\.c_str\(\),\s*dataSize\s*\);'
new_sha256_update = '''mbedtls_sha256_update(
        &sha256Context,
        (const unsigned char*)data,
        dataSize
    );'''
content = re.sub(sha256_update_pattern, new_sha256_update, content)

with open('/Users/szamosiattila/Downloads/mfkrtk01_v0.2.1_INS_DIAG.ino', 'w') as f:
    f.write(content)
