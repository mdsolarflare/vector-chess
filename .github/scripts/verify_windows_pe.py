#!/usr/bin/env python3
"""Verify Windows PE icon and VS_VERSION_INFO metadata on exported executables.

Uses only the Python standard library to parse PE headers, the `.rsrc` section,
`RT_VERSION` (`VS_FIXEDFILEINFO` + `StringFileInfo` key-value pairs), and
`RT_ICON` / `RT_GROUP_ICON` entries. Optionally compares icon resources against
an unmodified Godot Windows export template to confirm every default icon slot
was replaced and none fell back to Godot's solid-blue placeholder icon.
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import struct
import sys
import zlib
from typing import Dict, List, Optional, Tuple

RT_ICON = 3
RT_GROUP_ICON = 14
RT_VERSION = 16
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
VS_FFI_SIGNATURE = 0xFEEF04BD


def _align4(offset: int) -> int:
    return (offset + 3) & ~3


def _read_utf16z(buf: bytes, offset: int, limit: int) -> Tuple[str, int]:
    pos = offset
    while pos + 1 < limit:
        if buf[pos] == 0 and buf[pos + 1] == 0:
            return buf[offset:pos].decode("utf-16le", errors="replace"), pos + 2
        pos += 2
    return buf[offset:limit].decode("utf-16le", errors="replace"), limit


def _parse_four_part_version(val: str) -> Optional[Tuple[int, int, int, int]]:
    parts = val.split(".")
    if len(parts) != 4 or not all(p.isdigit() for p in parts):
        return None
    nums = tuple(int(p) for p in parts)
    if any(n < 0 or n > 0xFFFF for n in nums):
        return None
    return nums  # type: ignore[return-value]


def parse_pe_resources(data: bytes) -> Dict[int, List[bytes]]:
    """Return a mapping of numeric PE resource type ID -> list of raw payloads."""
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise ValueError("Not a valid PE file: missing MZ header")

    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    if pe_offset + 24 > len(data) or data[pe_offset : pe_offset + 4] != b"PE\x00\x00":
        raise ValueError("Not a valid PE file: missing PE signature")

    _, num_sections, _, _, _, opt_header_size, _ = struct.unpack_from(
        "<HHIIIHH", data, pe_offset + 4
    )
    opt_start = pe_offset + 24
    opt_end = opt_start + opt_header_size
    if opt_end > len(data):
        raise ValueError("Truncated PE optional header")

    if opt_start + 2 > opt_end:
        raise ValueError("Truncated PE optional header magic")
    magic = struct.unpack_from("<H", data, opt_start)[0]
    if magic == 0x10B:  # PE32
        num_rva_off = opt_start + 92
        dd_offset = opt_start + 96
    elif magic == 0x20B:  # PE32+
        num_rva_off = opt_start + 108
        dd_offset = opt_start + 112
    else:
        raise ValueError(f"Unsupported PE optional header magic: 0x{magic:x}")

    if num_rva_off + 4 > opt_end:
        raise ValueError("PE optional header missing NumberOfRvaAndSizes")
    num_rva_and_sizes = struct.unpack_from("<I", data, num_rva_off)[0]
    # Resource table is DataDirectory[2] (each entry is 8 bytes: RVA, Size).
    if num_rva_and_sizes < 3 or dd_offset + 24 > opt_end:
        raise ValueError("PE optional header does not contain a resource directory entry")
    rsrc_dir_rva, rsrc_dir_size = struct.unpack_from("<II", data, dd_offset + 16)
    if rsrc_dir_rva == 0 or rsrc_dir_size == 0:
        raise ValueError("PE file has no resource directory")

    sections: List[Tuple[str, int, int, int, int]] = []
    sec_table = opt_end
    for i in range(num_sections):
        off = sec_table + i * 40
        if off + 40 > len(data):
            raise ValueError("Truncated PE section table")
        raw_name = data[off : off + 8].split(b"\x00", 1)[0].decode("ascii", errors="replace")
        virt_size, virt_addr, raw_size, raw_ptr = struct.unpack_from("<IIII", data, off + 8)
        sections.append((raw_name, virt_addr, virt_size, raw_ptr, raw_size))

    def rva_to_file_offset(rva: int, size: int = 0) -> int:
        for _, vaddr, vsize, rptr, rsize in sections:
            if rsize == 0:
                continue
            rel = rva - vaddr
            if 0 <= rel < rsize and rel + size <= rsize:
                file_off = rptr + rel
                if file_off + size > len(data):
                    raise ValueError(f"RVA 0x{rva:x} extends past end of file")
                return file_off
        raise ValueError(f"RVA 0x{rva:x} (size {size}) does not fall within raw data of any PE section")

    rsrc_base = rva_to_file_offset(rsrc_dir_rva)
    resources: Dict[int, List[bytes]] = {}

    def walk_dir(dir_rel_offset: int, depth: int, type_id: int | None) -> None:
        dir_off = rsrc_base + dir_rel_offset
        if dir_off + 16 > len(data):
            raise ValueError("Truncated IMAGE_RESOURCE_DIRECTORY")
        _, _, _, _, num_named, num_id = struct.unpack_from("<IIHHHH", data, dir_off)
        total = num_named + num_id
        entry_off = dir_off + 16
        for i in range(total):
            cur = entry_off + i * 8
            if cur + 8 > len(data):
                raise ValueError("Truncated IMAGE_RESOURCE_DIRECTORY_ENTRY")
            name_or_id, data_or_subdir = struct.unpack_from("<II", data, cur)
            is_named = bool(name_or_id & 0x80000000)
            is_subdir = bool(data_or_subdir & 0x80000000)
            target = data_or_subdir & 0x7FFFFFFF

            cur_type = type_id
            if depth == 0:
                if is_named:
                    continue
                cur_type = name_or_id

            if is_subdir:
                if depth >= 3:
                    continue
                walk_dir(target, depth + 1, cur_type)
            elif cur_type is not None:
                entry_file_off = rsrc_base + target
                if entry_file_off + 16 > len(data):
                    raise ValueError("Truncated IMAGE_RESOURCE_DATA_ENTRY")
                payload_rva, payload_size, _, _ = struct.unpack_from("<IIII", data, entry_file_off)
                payload_off = rva_to_file_offset(payload_rva, payload_size)
                resources.setdefault(cur_type, []).append(
                    data[payload_off : payload_off + payload_size]
                )

    walk_dir(0, 0, None)
    return resources


def parse_version_info(
    version_blob: bytes,
) -> Tuple[Dict[str, str], Optional[Dict[str, Tuple[int, int, int, int]]]]:
    """Extract StringFileInfo key/value pairs and VS_FIXEDFILEINFO version tuples."""
    strings: Dict[str, str] = {}
    fixed_versions: Optional[Dict[str, Tuple[int, int, int, int]]] = None

    # Walk VS_VERSION_INFO -> StringFileInfo -> <lang-codepage> -> String entries.
    def walk_blocks(offset: int, limit: int, depth: int, parent_key: str) -> None:
        nonlocal fixed_versions
        pos = offset
        while pos + 6 <= limit:
            w_length, w_value_length, w_type = struct.unpack_from("<HHH", version_blob, pos)
            if w_length < 6:
                break
            node_end = min(pos + w_length, limit)
            key, cur = _read_utf16z(version_blob, pos + 6, node_end)
            cur = _align4(cur)

            if parent_key == "__STRING_TABLE__":
                if w_value_length > 0 and cur < node_end:
                    # For string entries (wType == 1), wValueLength is in UTF-16 code units.
                    byte_len = w_value_length * 2 if w_type == 1 else w_value_length
                    val_end = min(cur + byte_len, node_end)
                    val = (
                        version_blob[cur:val_end]
                        .decode("utf-16le", errors="replace")
                        .rstrip("\x00")
                    )
                else:
                    val = ""
                if key:
                    strings[key] = val
            else:
                if depth == 0 and key == "VS_VERSION_INFO" and w_value_length >= 52 and cur + 52 <= node_end:
                    sig, _, fv_ms, fv_ls, pv_ms, pv_ls = struct.unpack_from("<IIIIII", version_blob, cur)
                    if sig == VS_FFI_SIGNATURE:
                        fixed_versions = {
                            "FileVersion": (
                                (fv_ms >> 16) & 0xFFFF,
                                fv_ms & 0xFFFF,
                                (fv_ls >> 16) & 0xFFFF,
                                fv_ls & 0xFFFF,
                            ),
                            "ProductVersion": (
                                (pv_ms >> 16) & 0xFFFF,
                                pv_ms & 0xFFFF,
                                (pv_ls >> 16) & 0xFFFF,
                                pv_ls & 0xFFFF,
                            ),
                        }
                if w_value_length > 0:
                    val_bytes = w_value_length * 2 if w_type == 1 else w_value_length
                    cur = _align4(min(cur + val_bytes, node_end))
                if key == "StringFileInfo":
                    walk_blocks(cur, node_end, depth + 1, "StringFileInfo")
                elif parent_key == "StringFileInfo":
                    walk_blocks(cur, node_end, depth + 1, "__STRING_TABLE__")
                elif depth == 0:
                    walk_blocks(cur, node_end, depth + 1, key)

            next_pos = _align4(node_end)
            if next_pos <= pos:
                break
            pos = next_pos

    walk_blocks(0, len(version_blob), 0, "")
    return strings, fixed_versions


def _paeth_predictor(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _is_godot_blue_fallback_png(blob: bytes) -> bool:
    """Detect Godot TemplateModifier's solid #478cbf fallback PNG across all PNG filter modes."""
    if not blob.startswith(PNG_SIGNATURE):
        return False
    pos = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = compression = filter_method = interlace = -1
    idat_chunks: List[bytes] = []
    while pos + 8 <= len(blob):
        chunk_len, chunk_type = struct.unpack_from(">I4s", blob, pos)
        data_start = pos + 8
        data_end = data_start + chunk_len
        if data_end + 4 > len(blob):
            return False
        chunk_data = blob[data_start:data_end]
        if chunk_type == b"IHDR" and chunk_len >= 13:
            width, height, bit_depth, color_type, compression, filter_method, interlace = (
                struct.unpack_from(">IIBBBBB", chunk_data, 0)
            )
        elif chunk_type == b"IDAT":
            idat_chunks.append(chunk_data)
        elif chunk_type == b"IEND":
            break
        pos = data_end + 4

    # fill_with_godot_blue() writes non-interlaced 8-bit RGB8 (or RGBA8) filled with #478cbf.
    if (
        bit_depth != 8
        or color_type not in (2, 6)
        or compression != 0
        or filter_method != 0
        or interlace != 0
        or width <= 0
        or height <= 0
        or not idat_chunks
    ):
        return False

    bpp = 3 if color_type == 2 else 4
    expected_pixel = b"\x47\x8c\xbf" if bpp == 3 else b"\x47\x8c\xbf\xff"
    expected_row = expected_pixel * width
    stride = width * bpp

    try:
        raw = zlib.decompress(b"".join(idat_chunks))
    except zlib.error:
        return False
    if len(raw) != height * (1 + stride):
        return False

    prev_row = bytearray(stride)
    idx = 0
    for _ in range(height):
        flt = raw[idx]
        idx += 1
        scan = raw[idx : idx + stride]
        idx += stride
        cur_row = bytearray(stride)
        if flt == 0:  # None
            cur_row[:] = scan
        elif flt == 1:  # Sub
            for x in range(stride):
                left = cur_row[x - bpp] if x >= bpp else 0
                cur_row[x] = (scan[x] + left) & 0xFF
        elif flt == 2:  # Up
            for x in range(stride):
                cur_row[x] = (scan[x] + prev_row[x]) & 0xFF
        elif flt == 3:  # Average
            for x in range(stride):
                left = cur_row[x - bpp] if x >= bpp else 0
                cur_row[x] = (scan[x] + ((left + prev_row[x]) >> 1)) & 0xFF
        elif flt == 4:  # Paeth
            for x in range(stride):
                left = cur_row[x - bpp] if x >= bpp else 0
                up = prev_row[x]
                up_left = prev_row[x - bpp] if x >= bpp else 0
                cur_row[x] = (scan[x] + _paeth_predictor(left, up, up_left)) & 0xFF
        else:
            return False

        if cur_row != expected_row:
            return False
        prev_row = cur_row

    return True


def icon_hashes(resources: Dict[int, List[bytes]]) -> List[str]:
    return sorted(hashlib.sha256(blob).hexdigest() for blob in resources.get(RT_ICON, []))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify Windows PE version metadata and custom icon resources."
    )
    parser.add_argument("exe", type=pathlib.Path, help="Exported Windows .exe to verify")
    parser.add_argument(
        "--template",
        type=pathlib.Path,
        default=None,
        help="Optional unmodified Godot Windows export template to confirm icon replacement",
    )
    parser.add_argument(
        "--expect",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="Require StringFileInfo field KEY to equal VALUE (repeatable)",
    )
    parser.add_argument(
        "--forbid-substring",
        action="append",
        default=[],
        metavar="KEY=TEXT",
        help="Fail if StringFileInfo field KEY contains TEXT (case-insensitive, repeatable)",
    )
    parser.add_argument(
        "--dump",
        action="store_true",
        help="Print extracted StringFileInfo fields, VS_FIXEDFILEINFO, and icon summary",
    )
    args = parser.parse_args()

    try:
        exe_bytes = args.exe.read_bytes()
        resources = parse_pe_resources(exe_bytes)
    except (OSError, ValueError) as exc:
        print(f"ERROR: Failed to parse PE resources from {args.exe}: {exc}", file=sys.stderr)
        return 1

    version_blobs = resources.get(RT_VERSION, [])
    if not version_blobs:
        print(f"ERROR: {args.exe} has no RT_VERSION resource.", file=sys.stderr)
        return 1

    fields, fixed_versions = parse_version_info(version_blobs[0])
    exe_icon_blobs = resources.get(RT_ICON, [])
    exe_icons = icon_hashes(resources)
    exe_group_icons = resources.get(RT_GROUP_ICON, [])

    if args.dump:
        print(f"PE metadata for {args.exe}:")
        for k, v in sorted(fields.items()):
            print(f"  {k} = {v!r}")
        if fixed_versions:
            for k, v in sorted(fixed_versions.items()):
                print(f"  VS_FIXEDFILEINFO.{k} = {'.'.join(map(str, v))}")
        print(f"  RT_GROUP_ICON count = {len(exe_group_icons)}, RT_ICON count = {len(exe_icons)}")

    errors: List[str] = []

    if not exe_group_icons or not exe_icon_blobs:
        errors.append(
            f"Missing Windows icon resources (RT_GROUP_ICON={len(exe_group_icons)}, RT_ICON={len(exe_icon_blobs)})."
        )
    elif any(_is_godot_blue_fallback_png(blob) for blob in exe_icon_blobs):
        errors.append(
            f"Exported executable {args.exe} contains Godot's solid-blue fallback icon (#478cbf)."
        )

    for spec in args.expect:
        if "=" not in spec:
            errors.append(f"Invalid --expect argument {spec!r}; expected KEY=VALUE.")
            continue
        key, expected = spec.split("=", 1)
        actual = fields.get(key)
        if actual != expected:
            errors.append(
                f"PE StringFileInfo[{key!r}] mismatch: expected {expected!r}, got {actual!r}."
            )
        if key in ("FileVersion", "ProductVersion"):
            expected_tuple = _parse_four_part_version(expected)
            if expected_tuple is not None:
                if fixed_versions is None:
                    errors.append(
                        f"PE RT_VERSION missing VS_FIXEDFILEINFO to verify numeric {key}={expected!r}."
                    )
                elif fixed_versions.get(key) != expected_tuple:
                    errors.append(
                        f"PE VS_FIXEDFILEINFO[{key!r}] mismatch: expected {expected_tuple}, got {fixed_versions.get(key)}."
                    )

    for spec in args.forbid_substring:
        if "=" not in spec:
            errors.append(f"Invalid --forbid-substring argument {spec!r}; expected KEY=TEXT.")
            continue
        key, forbidden = spec.split("=", 1)
        actual = fields.get(key, "")
        if forbidden.lower() in actual.lower():
            errors.append(
                f"PE StringFileInfo[{key!r}] still contains forbidden text {forbidden!r}: {actual!r}."
            )

    if args.template is not None:
        try:
            template_resources = parse_pe_resources(args.template.read_bytes())
        except (OSError, ValueError) as exc:
            print(f"ERROR: Failed to parse template PE resources from {args.template}: {exc}", file=sys.stderr)
            return 1
        template_icons = icon_hashes(template_resources)
        if not template_icons:
            errors.append(f"Template {args.template} contained no RT_ICON entries to compare.")
        else:
            overlap = set(exe_icons) & set(template_icons)
            if overlap:
                errors.append(
                    f"Exported executable {args.exe} still shares {len(overlap)}/{len(exe_icons)} RT_ICON resource(s) with stock template {args.template}."
                )

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    print(
        f"Verified Windows PE resources for {args.exe}: "
        f"ProductName={fields.get('ProductName')!r}, "
        f"FileDescription={fields.get('FileDescription')!r}, "
        f"FileVersion={fields.get('FileVersion')!r}, "
        f"ProductVersion={fields.get('ProductVersion')!r}, "
        f"RT_ICON entries={len(exe_icons)}."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
