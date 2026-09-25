#!/usr/bin/env python3
"""Ad-hoc подпись 64-битного Mach-O (аналог `codesign -s -`), работает на Linux.

Добавляет LC_CODE_SIGNATURE с SuperBlob:
  - CodeDirectory (SHA-256, страницы по 4 КБ, флаг CS_ADHOC)
  - пустые Requirements
  - (опционально) Entitlements
  - пустой CMS-блоб (как у настоящего codesign для ad-hoc)
Этого достаточно, чтобы установщики (AltStore, SideStore, Sideloadly, ESign/zsign,
TrollStore) могли переподписать приложение своим сертификатом.

Использование: adhoc_sign.py <binary> <bundle-id> [Info.plist] [entitlements.plist]
"""
import hashlib
import struct
import sys

LC_SEGMENT_64 = 0x19
LC_CODE_SIGNATURE = 0x1D
MH_MAGIC_64 = 0xFEEDFACF

CSMAGIC_REQUIREMENTS = 0xFADE0C01
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_EMBEDDED_ENTITLEMENTS = 0xFADE7171
CSMAGIC_BLOBWRAPPER = 0xFADE0B01

CSSLOT_CODEDIRECTORY = 0
CSSLOT_INFOSLOT = 1
CSSLOT_REQUIREMENTS = 2
CSSLOT_ENTITLEMENTS = 5
CSSLOT_SIGNATURESLOT = 0x10000

CS_ADHOC = 0x2
CS_EXECSEG_MAIN_BINARY = 0x1
PAGE_SHIFT = 12
PAGE = 1 << PAGE_SHIFT
HASH_SIZE = 32


def align(n, a):
    return (n + a - 1) // a * a


def sign(path, ident, info_plist=None, entitlements=None):
    data = bytearray(open(path, 'rb').read())
    magic, _cpu, _sub, _ft, ncmds, sizeofcmds, _flags, _res = struct.unpack_from('<IiiIIIII', data, 0)
    if magic != MH_MAGIC_64:
        raise SystemExit('not a 64-bit little-endian Mach-O')

    off = 32
    linkedit = None
    text = None
    first_section_off = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', data, off)
        if cmd == LC_CODE_SIGNATURE:
            raise SystemExit('binary is already signed')
        if cmd == LC_SEGMENT_64:
            name = data[off + 8:off + 24].rstrip(b'\0').decode()
            fileoff, filesize = struct.unpack_from('<QQ', data, off + 40)
            nsects = struct.unpack_from('<I', data, off + 64)[0]
            if name == '__LINKEDIT':
                linkedit = off
            if name == '__TEXT':
                text = (fileoff, filesize)
                for s in range(nsects):
                    soff = struct.unpack_from('<I', data, off + 72 + s * 80 + 48)[0]
                    if soff and (first_section_off is None or soff < first_section_off):
                        first_section_off = soff
        off += cmdsize
    lc_end = off
    if linkedit is None or text is None:
        raise SystemExit('no __LINKEDIT/__TEXT segment')
    if first_section_off is not None and lc_end + 16 > first_section_off:
        raise SystemExit('no header padding for LC_CODE_SIGNATURE (link with -headerpad_max_install_names)')

    # --- считаем размер подписи ---
    code_limit = align(len(data), 16)
    data += b'\0' * (code_limit - len(data))
    n_code_slots = (code_limit + PAGE - 1) // PAGE
    ident_b = ident.encode() + b'\0'
    n_special = CSSLOT_ENTITLEMENTS if entitlements else CSSLOT_REQUIREMENTS
    cd_header = 88
    hash_offset = cd_header + len(ident_b) + n_special * HASH_SIZE
    cd_len = hash_offset + n_code_slots * HASH_SIZE

    requirements = struct.pack('>III', CSMAGIC_REQUIREMENTS, 12, 0)
    ent_blob = b''
    if entitlements:
        ent_blob = struct.pack('>II', CSMAGIC_EMBEDDED_ENTITLEMENTS, 8 + len(entitlements)) + entitlements
    cms = struct.pack('>II', CSMAGIC_BLOBWRAPPER, 8)

    blobs = [(CSSLOT_CODEDIRECTORY, None), (CSSLOT_REQUIREMENTS, requirements)]
    if ent_blob:
        blobs.append((CSSLOT_ENTITLEMENTS, ent_blob))
    blobs.append((CSSLOT_SIGNATURESLOT, cms))
    sb_header = 12 + 8 * len(blobs)
    total = sb_header + cd_len + sum(len(b) for _, b in blobs if b is not None)
    sig_size = align(total, 16)

    # --- правим заголовок: новая load-команда + размер __LINKEDIT ---
    struct.pack_into('<IIII', data, lc_end, LC_CODE_SIGNATURE, 16, code_limit, sig_size)
    struct.pack_into('<II', data, 16, ncmds + 1, sizeofcmds + 16)
    le_fileoff = struct.unpack_from('<Q', data, linkedit + 40)[0]
    le_filesize = code_limit + sig_size - le_fileoff
    le_vmsize = align(le_filesize, 0x4000)
    struct.pack_into('<Q', data, linkedit + 32, le_vmsize)
    struct.pack_into('<Q', data, linkedit + 48, le_filesize)

    # --- CodeDirectory ---
    special = {}
    special[CSSLOT_REQUIREMENTS] = hashlib.sha256(requirements).digest()
    if info_plist:
        special[CSSLOT_INFOSLOT] = hashlib.sha256(info_plist).digest()
    if ent_blob:
        special[CSSLOT_ENTITLEMENTS] = hashlib.sha256(ent_blob).digest()

    cd = bytearray(cd_len)
    struct.pack_into('>IIIIIIIII', cd, 0,
                     CSMAGIC_CODEDIRECTORY, cd_len, 0x20400, CS_ADHOC,
                     hash_offset, cd_header, n_special, n_code_slots, code_limit)
    struct.pack_into('>BBBBI', cd, 36, HASH_SIZE, 2, 0, PAGE_SHIFT, 0)  # SHA-256
    struct.pack_into('>III', cd, 44, 0, 0, 0)            # scatter, team, spare3
    struct.pack_into('>Q', cd, 56, 0)                    # codeLimit64
    struct.pack_into('>QQQ', cd, 64, text[0], text[1], CS_EXECSEG_MAIN_BINARY)
    cd[cd_header:cd_header + len(ident_b)] = ident_b
    for slot in range(1, n_special + 1):
        h = special.get(slot, b'\0' * HASH_SIZE)
        pos = hash_offset - slot * HASH_SIZE
        cd[pos:pos + HASH_SIZE] = h
    for i in range(n_code_slots):
        page = bytes(data[i * PAGE:min((i + 1) * PAGE, code_limit)])
        pos = hash_offset + i * HASH_SIZE
        cd[pos:pos + HASH_SIZE] = hashlib.sha256(page).digest()

    # --- SuperBlob ---
    blobs[0] = (CSSLOT_CODEDIRECTORY, bytes(cd))
    sb = bytearray(struct.pack('>III', CSMAGIC_EMBEDDED_SIGNATURE, total, len(blobs)))
    offset = sb_header
    for slot, blob in blobs:
        sb += struct.pack('>II', slot, offset)
        offset += len(blob)
    for _, blob in blobs:
        sb += blob
    sb += b'\0' * (sig_size - len(sb))

    open(path, 'wb').write(bytes(data) + bytes(sb))
    print(f'signed {path}: {n_code_slots} pages, signature {sig_size} bytes, id={ident}')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    info = open(sys.argv[3], 'rb').read() if len(sys.argv) > 3 else None
    ents = open(sys.argv[4], 'rb').read() if len(sys.argv) > 4 else None
    sign(sys.argv[1], sys.argv[2], info, ents)
