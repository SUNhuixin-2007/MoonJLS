#!/usr/bin/env python3
"""Exercise real files through the compiled MoonBit Node adapter."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "work" / "pydeps"))
import imagecodecs
import numpy as np


def main() -> None:
    output = ROOT / "work" / "file-tests"
    output.mkdir(parents=True, exist_ok=True)
    checks = []
    with tempfile.TemporaryDirectory(prefix="真实文件 ", dir=output) as directory:
        base = Path(directory)

        def call(*args: object, good: bool = True) -> dict:
            command = ["node", "scripts/moonjls.mjs", *map(str, args)]
            result = subprocess.run(command, cwd=ROOT, capture_output=True,
                                    encoding="utf-8", check=False)
            if good:
                assert result.returncode == 0, result.stderr
                return json.loads(result.stdout)
            assert result.returncode != 0, result.stdout
            return {}

        for bits, components, near, mode in [(8, 1, 0, "none"), (16, 3, 0, "line"),
                                            (12, 3, 3, "sample"), (8, 4, 1, "sample"),
                                            (8, 2, 0, "none"), (8, 3, 0, "none")]:
            width, height = 64, 48
            maximum = (1 << bits) - 1
            values = (np.arange(width * height * components, dtype=np.uint64) * 331 + 17) & maximum
            samples = values.astype(np.uint8 if bits <= 8 else np.uint16)
            payload = samples.astype("u1" if bits <= 8 else ">u2").tobytes()
            pam = components in (2, 4)
            if pam:
                label = "GRAYSCALE_ALPHA" if components == 2 else "RGB_ALPHA"
                header = f"P7\nWIDTH {width}\nHEIGHT {height}\nDEPTH {components}\nMAXVAL {maximum}\nTUPLTYPE {label}\nENDHDR\n"
            else:
                header = f"{'P5' if components == 1 else 'P6'}\n{width} {height}\n{maximum}\n"
            name = f"{bits}位 {components}通道 n{near} {mode}"
            source = base / f"{name}.{'pam' if pam else 'pnm'}"
            source.write_bytes(header.encode("ascii") + payload)
            packed = base / f"{name}.jls"
            report = call("encode", source, packed, "--near", near, "--interleave", mode)
            independent = imagecodecs.jpegls_decode(packed.read_bytes()).reshape(-1).astype(np.int64)
            assert int(np.max(np.abs(independent - samples.astype(np.int64)))) <= near
            if not pam:
                assert report["full_pixel_array"] is False
                assert report["largest_read_bytes"] <= max(256, width * components * (1 if bits <= 8 else 2))
            inspected = call("inspect", packed)
            assert inspected["entropy_validated"] is False
            assert inspected["info"]["frame"]["bits_per_sample"] == bits
            restored = base / f"{name}-restored.{'pam' if pam else 'pnm'}"
            decoded = call("decode", packed, restored)
            expected = independent.astype("u1" if bits <= 8 else ">u2").tobytes()
            assert restored.read_bytes() == header.encode("ascii") + expected
            assert int(decoded["written_bytes"]) == restored.stat().st_size
            # Existing files and the input itself survive rejected writes.
            before = restored.read_bytes()
            call("decode", packed, restored, good=False)
            assert restored.read_bytes() == before
            call("encode", source, source, good=False)
            assert source.read_bytes() == header.encode("ascii") + payload
            checks.append(name)

        for bits in (8, 16):
            width = 65536
            source = base / f"wide-{bits}.pgm"
            packed = base / f"wide-{bits}.jls"
            restored = base / f"wide-{bits}-restored.pgm"
            pixels = np.full(width, 35, dtype=np.uint8 if bits == 8 else np.uint16)
            payload = pixels.astype("u1" if bits == 8 else ">u2").tobytes()
            header = f"P5\n{width} 1\n{(1 << bits) - 1}\n".encode("ascii")
            source.write_bytes(header + payload)
            encoded = call("encode", source, packed)
            assert encoded["frame"]["width"] == width
            assert encoded["full_pixel_array"] is False
            independent = imagecodecs.jpegls_decode(packed.read_bytes()).reshape(-1)
            assert np.array_equal(independent, pixels)
            call("decode", packed, restored)
            assert restored.read_bytes() == source.read_bytes()
            checks.append(f"wide PNM/JPEG-LS {width}x1 {bits}-bit exact roundtrip")

        ascii_source = base / "ascii.pgm"
        ascii_source.write_bytes(b"P2\n3 1\n255\n0 10 255\n")
        ascii_wire = base / "ascii.jls"
        call("encode", ascii_source, ascii_wire)
        assert imagecodecs.jpegls_decode(ascii_wire.read_bytes()).reshape(-1).tolist() == [0, 10, 255]
        ascii_pam = base / "ascii.pam"
        call("decode", ascii_wire, ascii_pam, "--pam")
        assert ascii_pam.read_bytes().endswith(b"ENDHDR\n\x00\x0a\xff")
        checks.append("ASCII input and explicit PAM export")

        for index, data in enumerate([b"P5\n2 2\n255\n\x00", b"P5\n1 1\n1000\n\x00\x01",
                                      b"\xff\xd8\xff", b"not an image"]):
            source = base / f"broken-{index}"
            destination = base / f"must-not-remain-{index}"
            source.write_bytes(data)
            call("decode" if index == 2 else "encode", source, destination, good=False)
            assert not destination.exists(), "failed operation leaked a partial output file"
        invalid = base / "invalid-option.jls"
        call("encode", ascii_source, invalid, "--near", 999, good=False)
        assert not invalid.exists()
        checks.append("truncated/invalid inputs, unsupported MAXVAL, option rejection and partial-output cleanup")

    report = {"result": "PASS", "cases": checks, "independent": imagecodecs.jpegls_version(),
              "scope": "Real temporary files, Unicode paths, compiled MoonBit codec; Node performs I/O only"}
    target = ROOT / "work" / "validation" / "file_cli.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: {len(checks)} real-file scenarios including overwrite protection and failed-output cleanup")


if __name__ == "__main__":
    main()
