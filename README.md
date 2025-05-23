# Oracle QR Code Generator (PL/SQL – PNG & Base64)

This simple **PL/SQL package** allows you to generate **QR codes directly in Oracle**.  
You can create QR codes in **PNG format** or get them as **Base64-encoded strings**, making it easy to integrate with web applications or export as binary/image data.

---

## ✨ Features

- Generate QR codes from any string or URL.
- Output as **PNG** binary (**BLOB**).
- Output as **Base64-encoded** string.
- Easy to use in SQL or PL/SQL environments.

---

## 🚀 How to Test

You can test the package using the following SQL queries in **SQL*Plus**, **SQL Developer**, or any Oracle-compatible SQL tool:

```sql
-- Generate QR code as Base64-encoded string
set define off
SELECT hc_qr.qr_base64('https://www.youtube.com/@HarryC04-DBA') FROM dual;

-- Check the length of the Base64 string (useful for debugging)
SELECT LENGTH(hc_qr.qr_base64('https://www.youtube.com/@HarryC04-DBA')) FROM dual;

-- Generate QR code as PNG (BLOB output)
SELECT hc_qr.get_qrcode_png(
           p_value => 'https://www.youtube.com/@HarryC04-DBA'
       ) FROM dual;
