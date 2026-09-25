#!/usr/bin/env python3
"""Минимальный zipalign: выравнивает несжатые файлы APK по 4 байтам (.so — по 4096).
Запускать ДО подписи (apksigner). Использование: zipalign.py in.apk out.apk"""
import sys
import zipfile

src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, 'w') as zout:
    for info in zin.infolist():
        data = zin.read(info.filename)
        out = zipfile.ZipInfo(info.filename, date_time=info.date_time)
        out.compress_type = info.compress_type
        out.external_attr = info.external_attr
        out.create_system = info.create_system
        if info.compress_type == zipfile.ZIP_STORED:
            align = 4096 if info.filename.endswith('.so') else 4
            offset = zout.fp.tell() + 30 + len(info.filename.encode('utf-8'))
            out.extra = b'\0' * ((align - offset % align) % align)
        zout.writestr(out, data)
