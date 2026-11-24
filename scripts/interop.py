#!/usr/bin/env python3
"""Independent CharLS pixel checks; no codec algorithm is implemented here."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "work" / "pydeps"))
import imagecodecs as codecs
import numpy as np

VERSION = "2026.11.11"


def cases() -> list[dict]:
    result = []
    for bits in (2, 4, 8, 10, 12, 16):
        maximum = (1 << bits) - 1
        for components in (1, 3, 4):
            modes = (0,) if components == 1 else (0, 1, 2)
            for near in (0, 1):
                for pattern in range(3):
                    width, height = 19, 11
                    count = width * height * components
                    values = []
                    for index in range(count):
                        x = (index // components) % width
                        y = index // (width * components)
                        if pattern == 0:
                            value = maximum if x >= 9 else 0
                        elif pattern == 1:
                            value = (x * 13 + y * 97 + index % components * 73) & maximum
                        else:
                            value = ((index * 3331 + index * index % 65521 * 19 + 1493) ^ (index << 5)) & maximum
                        values.append(value)
                    for mode in modes:
                        result.append(dict(width=width, height=height, bits=bits,
                                           components=components, near=near, interleave=mode,
                                           samples=values, label=f"b{bits}-c{components}-n{near}-p{pattern}-i{mode}"))
    for width, height in ((1, 1), (1, 65), (130, 2), (2, 130)):
        for value in (0, 65535):
            result.append(dict(width=width, height=height, bits=16, components=1,
                               near=0, interleave=0, samples=[value] * (width * height),
                               label=f"edge-{width}x{height}-{value}"))
    for bits in (8, 16):
        for mode in (1, 2):
            for transform in (1, 2, 3):
                maximum = (1 << bits) - 1
                values = [(i * 31337 + i * i * 7) & maximum for i in range(13 * 7 * 3)]
                result.append(dict(width=13, height=7, bits=bits, components=3, near=0,
                                   interleave=mode, transform=transform, samples=values,
                                   label=f"hp{transform}-b{bits}-i{mode}"))
    for bits, near in ((4, 7), (8, 127), (10, 255), (12, 255), (16, 255)):
        maximum = (1 << bits) - 1
        result.append(dict(width=23, height=9, bits=bits, components=1,
                           near=near, interleave=0,
                           samples=[(i * 331 + i*i*7) & maximum for i in range(207)],
                           label=f"high-near-b{bits}-n{near}"))
    for bits in (8, 16):
        result.append(dict(width=65536, height=1, bits=bits, components=1,
                           near=0, interleave=0, fill=17, label=f"wide-{bits}"))
    for components in (1, 3, 4):
        result.append(dict(width=7, height=5, bits=8, components=components,
                           near=0, interleave=0 if components == 1 else 1,
                           spiff=True, samples=[i * 19 % 256 for i in range(35 * components)],
                           label=f"spiff-{components}"))
    return result


def extension_cases() -> list[dict]:
    result = []
    for components in (1, 2, 3, 4):
        # CharLS rejects interleaved two-component scans; those have local tests only.
        for mode in ((0,) if components in (1, 2) else (0, 1, 2)):
            for near in (0, 2):
                base = dict(width=17, height=11, bits=12, components=components,
                            interleave=mode, near=near,
                            samples=[(i * 331 + i*i*7) & 4095 for i in range(187 * components)])
                for interval in (1, 3, 20):
                    result.append(dict(**base, restart=interval,
                                       label=f"restart-{interval}-c{components}-i{mode}-n{near}"))
                if components == 1 or mode != 0:
                    result.append(dict(**base, encoder="push", label=f"push-c{components}-i{mode}-n{near}"))
    for maximum in (1023, 32767, 65535):
        bits = max(2, maximum.bit_length())
        for near in (0, min(3, maximum // 2)):
            result.append(dict(width=29, height=5, bits=bits, components=1, near=near,
                               interleave=0, samples=[i * 47 % (maximum + 1) for i in range(145)],
                               preset=dict(maximum=maximum, threshold1=0, threshold2=0, threshold3=0, reset=7),
                               label=f"custom-max{maximum}-n{near}"))
    for bits in (8, 16):
        maximum = (1 << bits) - 1
        for components in (1, 3):
            for mode in ((0,) if components == 1 else (0, 1, 2)):
                for near in (0, 3):
                    thresholds = (5, 11, 25) if bits == 8 else (100, 400, 1000)
                    result.append(dict(width=19, height=13, bits=bits, components=components,
                                       near=near, interleave=mode,
                                       samples=[(i * 239 + i*i*3) & maximum for i in range(247 * components)],
                                       preset=dict(maximum=maximum, threshold1=thresholds[0], threshold2=thresholds[1], threshold3=thresholds[2], reset=64 if mode == 2 else 13),
                                       label=f"thresholds-b{bits}-c{components}-i{mode}-n{near}"))
    return result


def array(request: dict) -> np.ndarray:
    shape = (request["height"], request["width"])
    if request["components"] != 1:
        shape += (request["components"],)
    if "fill" in request:
        return np.full(shape, request["fill"], dtype=np.uint8 if request["bits"] <= 8 else np.uint16)
    return np.array(request["samples"], dtype=np.uint8 if request["bits"] <= 8 else np.uint16).reshape(shape)


def external_bytes(request: dict) -> bytes:
    pixels = array(request)
    if request["components"] > 1 and request["interleave"] == 0:
        pixels = np.moveaxis(pixels, -1, 0).copy()
    return codecs.jpegls_encode(pixels, level=request["near"],
                               bitspersample=request["bits"], planar=(request["interleave"] == 0) if request["components"] > 1 else None,
                               transformation=request.get("transform", 0), spiff=request.get("spiff", False))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate-fixtures", action="store_true")
    parser.add_argument("--quick", action="store_true")
    args = parser.parse_args()
    if args.quick and args.generate_fixtures:
        parser.error("--quick cannot regenerate the full committed golden corpus")
    assert codecs.__version__ == VERSION, codecs.__version__
    if not args.generate_fixtures:
        (ROOT / "work" / "validation" / "interop.json").unlink(missing_ok=True)
    selected = cases()
    if args.quick:
        selected = selected[:12]
    if args.generate_fixtures:
        fixtures = []
        for request in selected:
            wire = external_bytes(request)
            fixtures.append({"request": request, "hex": wire.hex(),
                             "decoded": codecs.jpegls_decode(wire).reshape(-1).tolist(),
                             "sha256": hashlib.sha256(wire).hexdigest()})
        document = {"oracle": f"imagecodecs=={VERSION}", "engine": codecs.jpegls_version(),
                    "cases": fixtures}
        target = ROOT / "fixtures" / "charls-golden.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(document, separators=(",", ":")) + "\n", encoding="utf-8")
        (ROOT / "fixtures" / "gray8.jls").write_bytes(external_bytes(next(r for r in selected if r["bits"] == 8 and r["components"] == 1)))
        print(f"Generated {len(fixtures)} independently encoded images")
        return
    subprocess.run(["moon", "build", "cmd/interop", "--target", "js", "--deny-warn"], cwd=ROOT, check=True)
    cli = ROOT / "_build" / "js" / "debug" / "build" / "cmd" / "interop" / "interop.js"

    def invoke(operation: str, request: dict) -> dict:
        output = subprocess.run(["node", str(cli), operation, json.dumps(request, separators=(",", ":"))],
                                cwd=ROOT, check=True, capture_output=True, encoding="utf-8")
        answer = json.loads(output.stdout)
        if "error" in answer:
            raise AssertionError(f"{operation}: {answer['error']} ({request.get('label', '')})")
        return answer

    golden = json.loads((ROOT / "fixtures" / "charls-golden.json").read_text(encoding="utf-8"))
    by_label = {case["request"]["label"]: case for case in golden["cases"]}
    for index, request in enumerate(selected):
        original = array(request).astype(np.int64)
        reference = external_bytes(request)
        expected = codecs.jpegls_decode(reference).reshape(-1).tolist()
        fixture = by_label[request["label"]]
        assert fixture["hex"] == reference.hex(), ("golden bytes changed", request["label"])
        assert fixture["sha256"] == hashlib.sha256(reference).hexdigest()
        assert fixture["decoded"] == expected
        answer = invoke("decode", {"hex": reference.hex(), "label": request["label"]})
        assert answer["samples"] == expected, ("external decode mismatch", request["label"])
        encoded = bytes.fromhex(invoke("encode", request)["hex"])
        independent = codecs.jpegls_decode(encoded).astype(np.int64)
        local = invoke("decode", {"hex": encoded.hex(), "label": request["label"]})
        assert local["samples"] == independent.reshape(-1).tolist(), ("self decode differs from CharLS", request["label"])
        error = int(np.max(np.abs(independent - original)))
        assert error <= request["near"], (request["label"], error, request["near"])
        if (index + 1) % 40 == 0:
            print(f"Validated {index + 1}/{len(selected)} images", flush=True)
    extensions = extension_cases() if not args.quick else extension_cases()[:4]
    for request in extensions:
        encoded = bytes.fromhex(invoke("encode", request)["hex"])
        independent = codecs.jpegls_decode(encoded).astype(np.int64)
        local = invoke("decode", {"hex": encoded.hex(), "label": request["label"]})
        assert local["samples"] == independent.reshape(-1).tolist(), request["label"]
        assert int(np.max(np.abs(independent - array(request).astype(np.int64)))) <= request["near"], request["label"]
    print(f"Validated {len(extensions)} outgoing restart/push/custom-preset cases", flush=True)
    report = {"oracle": f"imagecodecs=={VERSION}", "engine": codecs.jpegls_version(),
              "cases": len(selected), "outgoing_extensions": len(extensions), "directions": ["CharLS -> MoonJLS", "MoonJLS -> CharLS"],
              "checks": ["exact reconstructed pixels", "maximum absolute error <= NEAR",
                         "2/4/8/10/12/16-bit", "one/two/three/four channels", "all interleave modes",
                         "runs/noise/gradients", "row boundaries", "HP1/2/3 extension", "SPIFF", "LSE4 extended dimensions",
                         "restart intervals (outgoing)", "push encoder (outgoing)", "explicit full-range MAXVAL/custom T1/T2/T3/RESET (outgoing)"], "reference_limits": ["imagecodecs encoding rejects two-channel input shapes",
                           "CharLS decoding rejects interleaved two-channel scans",
                           "sample interleave plus non-default RESET has local tests only; external sample tests use RESET=64",
                           "non-full-range MAXVAL is explicitly unsupported by MoonJLS public codec profile"], "result": "PASS"}
    output = ROOT / "work" / "validation" / "interop.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: {len(selected)} images in both directions + {len(extensions)} outgoing extensions")


if __name__ == "__main__":
    main()
