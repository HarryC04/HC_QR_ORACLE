# Oracle QR Code Generator (PL/SQL – PNG & Base64)

This simple **PL/SQL package** allows you to generate **QR codes directly in Oracle**.  
You can create QR codes in **PNG format** or get them as **Base64-encoded strings**, making it easy to integrate with web applications or export as binary/image data.

---

## 🛠 About This Package

This package is a **simplified and optimized version** of a native QR code generator originally found in Oracle APEX.

The original source code was:

- Adapted from internal APEX utilities.
- Cleaned and stripped down to include **only the essential logic**.
- Reduced in size by removing unused procedures and extra dependencies.

The package has been **successfully tested** in the following Oracle database versions:

- ✅ Oracle 11g  
- ✅ Oracle 19c

It is expected to work without issues on **Oracle 21c and future versions** as it relies on standard PL/SQL and binary output (BLOB).

> ⚙️ This version focuses on portability, simplicity, and integration with back-end PL/SQL logic that may require QR code output in either PNG or Base64 formats.

----

## ✨ Features

- Generate QR codes from any string or URL.
- Output as **PNG** binary (**BLOB**).
- Output as **Base64-encoded** string.
- Easy to use in SQL or PL/SQL environments.

---

## 📦 Installation

To install the package, simply run the following two files in your Oracle environment:

- `HC_QR.pks` – **Package specification**
- `HC_QR.pkb` – **Package body**

You can execute them using tools like **SQL\*Plus** or **SQL Developer**:

```sql
@HC_QR.pks
@HC_QR.pkb

--

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
