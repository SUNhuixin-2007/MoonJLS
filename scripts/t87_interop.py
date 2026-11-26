"""Host I/O for the unmodified ITU T.87 reference executables. No codec algorithm.
Reference binaries/license stay in ignored work/, not in the BSD project distribution.
"""
from pathlib import Path
import subprocess,json,hashlib,sys,argparse,platform,os,tempfile
from datetime import datetime,timezone,timedelta
ROOT=Path(__file__).resolve().parents[1]
REFERENCE=ROOT/"work/standards/jlsrefV100"
FIXTURES=ROOT/"fixtures/t87-maxval"
MANIFEST=FIXTURES/"golden.json"
REFERENCE_URL="https://www.itu.int/rec/dologin_pub.asp?id=T-REC-T.87-199806-I!!ZPF-E&lang=e&type=items"
REFERENCE_ZIP_SHA256="085285f0552ef0b6ebcf29bc5a6d3bc0d6bda0408e9f2f1c138be2e55200814f"
BINARY_HASHES={
 "loco16d.exe":"f080d7cd7722ffbbd4e8887a229cb023e2c7ca471a69f6730d2ac41a09a6e7f5",
 "loco16e.exe":"a0573719d3b76d980d80c50fe51fdaf806267c54c58eacf720dc8f79fd4c2766",
 "locod.exe":"36516cba57c7706a76d9ae3f21c4e35f2b3bd1a7a0ef7ca0f0124f18b78015c0",
 "locoe.exe":"20c3e1f2e61464438c6e348bdb187d17d1ea25d44c5a429bca948fad0426c699",
 "nloco16d.exe":"84682e13e6a12cd60e758cfd8d4c1c4c82d49bd415b76ae0c58a745bc71e4b00",
 "nloco16e.exe":"516ca3ca2093e62e8c9596c5f9927933a442af1305dbea0cd7921842ad0ce32e",
 "nlocod.exe":"7cbc4c9506c9031a53b863793ad27c6bcb90f83c7fa257c53a90e83c5a6d5e86",
 "nlocoe.exe":"706a81309493b6a8edeb3cb1cbfce810282aa05daeca22ae58af296bcf7ee3c3"
}

def read_pnm(path):
    data=Path(path).read_bytes();at=0
    def token():
        nonlocal at
        while at<len(data):
            if data[at] in b" \t\r\n\v\f":at+=1
            elif data[at]==35:
                while at<len(data) and data[at] not in b"\r\n":at+=1
            else:break
        start=at
        while at<len(data) and data[at] not in b" \t\r\n\v\f#":at+=1
        return data[start:at]
    kind=token();width=int(token());height=int(token());maximum=int(token())
    assert kind in (b"P5",b"P6")
    assert data[at] in b" \t\r\n\v\f"
    first=data[at];at+=1
    if first==13 and data[at:at+1]==b"\n":at+=1
    count=width*height*(1 if kind==b"P5" else 3)
    raster=data[at:];step=1 if maximum<256 else 2
    assert len(raster)==count*step,(path,len(raster),count,step)
    values=list(raster) if step==1 else [int.from_bytes(raster[i:i+2],"big") for i in range(0,len(raster),2)]
    return dict(width=width,height=height,maximum=maximum,components=1 if kind==b"P5" else 3,samples=values)

def write_pnm(path,request,components):
    assert len(components) in (1,3)
    width,height,maximum=request["width"],request["height"],request["preset"]["maximum"]
    values=[request["samples"][i*request["components"]+c] for i in range(width*height) for c in components]
    raster=bytes(values) if maximum<256 else b"".join(v.to_bytes(2,"big") for v in values)
    Path(path).write_bytes(f"{'P5' if len(components)==1 else 'P6'}\n{width} {height}\n{maximum}\n".encode()+raster)

def program(request,encode):
    return REFERENCE/(("n" if request["near"] else "")+"loco"+("16" if request["preset"]["maximum"]>=256 else "")+("e" if encode else "d")+".exe")

def run(command,directory):
    result=subprocess.run([str(x) for x in command],cwd=directory,capture_output=True,timeout=30)
    if result.returncode:
        raise RuntimeError(f"T.87 reference exit {result.returncode}: "+(result.stdout+result.stderr).decode(errors="replace")[-1600:])

def encode(request,directory):
    directory=Path(directory).resolve();directory.mkdir(parents=True,exist_ok=True)
    components=request["components"];mode=request["interleave"]
    if components==3 and mode in (1,2):
        inputs=[directory/"input.ppm"];write_pnm(inputs[0],request,[0,1,2])
    else:
        assert mode!=2,"Reference sample interleave accepts PPM/RGB only"
        inputs=[directory/f"input-{c}.pgm" for c in range(components)]
        for c,path in enumerate(inputs):write_pnm(path,request,[c])
    output=directory/"reference.jls"
    command=[program(request,True),f"-c{mode}"]
    if request["near"]:command.append(f"-e{request['near']}")
    for name,flag in (("reset","-r"),("threshold1","-Ta"),("threshold2","-Tb"),("threshold3","-Tc")):
        if request["preset"].get(name):command.append(flag+str(request["preset"][name]))
    run(command+inputs+["-o"+str(output)],directory)
    return output.read_bytes()

def decode(data,request,directory):
    directory=Path(directory).resolve();directory.mkdir(parents=True,exist_ok=True)
    source=directory/"source.jls";source.write_bytes(data)
    components=request["components"];mode=request["interleave"]
    if components==3 and mode in (1,2):
        outputs=[directory/"decoded.ppm"];command=[program(request,False),"-P",source,*outputs]
    else:
        outputs=[directory/f"decoded-{c}.pgm" for c in range(components)]
        command=[program(request,False),source,*outputs]
    run(command,directory)
    decoded=[read_pnm(path) for path in outputs]
    assert all(d["width"]==request["width"] and d["height"]==request["height"] for d in decoded)
    assert all(d["maximum"]==request["preset"]["maximum"] for d in decoded)
    if len(decoded)==1:return decoded[0]["samples"]
    return [decoded[c]["samples"][i] for i in range(request["width"]*request["height"]) for c in range(components)]


def maximum_error(a,b):
    assert len(a)==len(b), "sample counts differ"
    return max((abs(x-y) for x,y in zip(a,b)),default=0)

def sha256(data):
    return hashlib.sha256(data).hexdigest()

def selected_cases():
    result=[]
    for maximum in (3,15,31,100,128,255,256,1000,1024,4095,4096,65534):
        levels=sorted({0,1,min(3,maximum//2),min(255,maximum//2)})
        for near in levels:
            for pattern in ("step","gradient","noise"):
                width,height=17,9
                values=[]
                for i in range(width*height):
                    x,y=i%width,i//width
                    value=(0 if x<width//2 else maximum) if pattern=="step" else ((x*13+y*37)%(maximum+1) if pattern=="gradient" else ((i*331+i*i*7)^(i<<5))%(maximum+1))
                    values.append(value)
                # The 1999 reference's low-MAXVAL near defaults differ from the
                # T.87 C.5 calculation. Explicit legal presets avoid emitting an
                # implicit-default stream with incompatible context thresholds.
                thresholds=(near+1,min(maximum,2*(near+1)),min(maximum,3*(near+1))) if maximum<128 and near>0 else (0,0,0)
                result.append(dict(width=width,height=height,bits=max(2,maximum.bit_length()),components=1,
                                   interleave=0,near=near,samples=values,label=f"max{maximum}-near{near}-{pattern}",
                                   preset=dict(maximum=maximum,threshold1=thresholds[0],threshold2=thresholds[1],threshold3=thresholds[2],reset=64 if thresholds[0] else 0)))
    for width,height in ((1,1),(1,19),(33,2)):
        for near in (0,3):
            result.append(dict(width=width,height=height,bits=10,components=1,interleave=0,near=near,
                               samples=[1000]*(width*height),label=f"edge-max1000-{width}x{height}-near{near}",
                               preset=dict(maximum=1000,threshold1=0,threshold2=0,threshold3=0,reset=0)))
    return result

def verified_reference():
    if platform.system()!="Windows":return False
    if not all((REFERENCE/name).is_file() for name in BINARY_HASHES):return False
    for name,expected in BINARY_HASHES.items():
        assert sha256((REFERENCE/name).read_bytes())==expected, f"unrecognized reference binary: {name}"
    return True

def reference_metadata():
    return dict(name="ITU-T T.87 accompanying JPEG-LS Reference Software V1.00X (1999-03-04)",
                source=REFERENCE_URL,inner_archive="jlsrefV100.zip",inner_archive_sha256=REFERENCE_ZIP_SHA256,
                binary_sha256=BINARY_HASHES,
                license="HP/ISO/IEC/ITU testing-product-conformance-only; original binaries and notices remain in ignored work/ and are not redistributed",
                known_limits=["MAXVAL 1/2 are rejected by the reference executable", "For MAXVAL<128 with NEAR>0 these vectors use explicit legal thresholds/RESET. The legacy reference implicit threshold defaults differ from final T.87 C.5; they are not treated as standard-default evidence."])

def generate(requests):
    target=ROOT/"work/t87-validation/generation";target.mkdir(parents=True,exist_ok=True)
    rows=[]
    FIXTURES.mkdir(parents=True,exist_ok=True)
    for request in requests:
        case=target/request["label"]
        wire=encode(request,case/"encode")
        reconstructed=decode(wire,request,case/"decode")
        error=maximum_error(request["samples"],reconstructed)
        assert error<=request["near"], (request["label"],error)
        rows.append(dict(request=request,reference_hex=wire.hex(),reference_sha256=sha256(wire),
                         reference_decoded=reconstructed,maximum_error=error))
        if request["label"] in ("max1000-near0-noise","max1000-near3-noise"):
            prefix=FIXTURES/"examples"/f"max1000-near{request['near']}"
            prefix.parent.mkdir(exist_ok=True)
            write_pnm(str(prefix)+"-input.pgm",request,[0])
            Path(str(prefix)+"-reference.jls").write_bytes(wire)
            Path(str(prefix)+"-reference-decoded.pgm").write_bytes((case/"decode/decoded-0.pgm").read_bytes())
    document=dict(format="moonjls.t87.maxval.v1",reference=reference_metadata(),cases=rows,
                  coverage="Synthetic grayscale 2..16-bit MAXVAL cases; not full T.87 certification. MAXVAL 1/2 are excluded because this reference tool rejects alphabet sizes below four.")
    MANIFEST.write_text(json.dumps(document,separators=(",",":"))+"\n",encoding="utf-8")
    print(f"Generated {len(rows)} official-reference input vectors; no MoonJLS outputs used as expectations")

def build_bridge():
    subprocess.run(["moon","build","cmd/interop","--target","js","--deny-warn"],cwd=ROOT,check=True)
    return ROOT/"_build/js/debug/build/cmd/interop/interop.js"

def invoke(bridge,operation,request):
    result=subprocess.run(["node",str(bridge),operation,json.dumps(request,separators=(",",":"))],
                          cwd=ROOT,check=True,capture_output=True,encoding="utf-8",timeout=30)
    value=json.loads(result.stdout)
    if "error" in value:raise AssertionError(f"{operation}: {value['error']} ({request.get('label','')})")
    return value

def verify(args,requests,live):
    output=ROOT/"work/validation/t87-maxval.json";output.parent.mkdir(parents=True,exist_ok=True)
    output.unlink(missing_ok=True)
    document=json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert document["reference"]["inner_archive_sha256"]==REFERENCE_ZIP_SHA256
    saved={row["request"]["label"]:row for row in document["cases"]}
    bridge=build_bridge();results=[];examples={}
    for index,request in enumerate(requests):
        row=saved[request["label"]];assert row["request"]==request
        wire=bytes.fromhex(row["reference_hex"])
        assert sha256(wire)==row["reference_sha256"]
        case=ROOT/"work/t87-validation/check"/request["label"]
        if live:
            regenerated=encode(request,case/"incoming-encode")
            assert regenerated==wire,("reference golden changed",request["label"])
            assert decode(wire,request,case/"incoming-decode")==row["reference_decoded"]
        answer=invoke(bridge,"decode",dict(hex=wire.hex(),label=request["label"]))
        assert (answer["width"],answer["height"],answer["bits"],answer["components"])==(request["width"],request["height"],request["bits"],1)
        assert answer["samples"]==row["reference_decoded"],("incoming pixels differ",request["label"])
        assert maximum_error(request["samples"],answer["samples"])<=request["near"]
        item=dict(label=request["label"],maximum=request["preset"]["maximum"],near=request["near"],incoming="PASS",incoming_reference_sha256=row["reference_sha256"])
        if live:
            outgoing=bytes.fromhex(invoke(bridge,"encode",request)["hex"])
            external=decode(outgoing,request,case/"outgoing-decode")
            local=invoke(bridge,"decode",dict(hex=outgoing.hex(),label=request["label"]))["samples"]
            assert external==local,("outgoing reconstruction differs",request["label"])
            error=maximum_error(request["samples"],external);assert error<=request["near"]
            info=invoke(bridge,"inspect",dict(hex=outgoing.hex(),label=request["label"]))
            assert info["scans"][0]["preset"]["maximum"]==request["preset"]["maximum"]
            item.update(outgoing="PASS",outgoing_sha256=sha256(outgoing),outgoing_maximum_error=error)
            if request["label"] in ("max1000-near0-noise","max1000-near3-noise"):
                examples[request["label"]]=(request,outgoing,(case/"outgoing-decode/decoded-0.pgm").read_bytes(),item)
        results.append(item)
        if (index+1)%30==0:print(f"Validated {index+1}/{len(requests)} MAXVAL vectors",flush=True)
    full_range=sum(r["preset"]["maximum"]==(1<<r["bits"])-1 for r in requests)
    report=dict(reference=reference_metadata(),recorded_at=datetime.now(timezone(timedelta(hours=8))).isoformat(),
                result="PASS" if live else "PASS_GOLDEN_INPUT_ONLY",mode="live-bidirectional" if live else "golden-input-only",
                cases=len(results),incoming_pass=len(results),outgoing_live_pass=len(results) if live else 0,
                non_full_range_cases=len(results)-full_range,full_range_controls=full_range,
                directions=["Official T.87 -> MoonJLS"]+(["MoonJLS -> Official T.87"] if live else []),
                limitations=["Reference binaries run on Windows only; Linux/macOS CI validates committed official inputs, not a live external outgoing decoder", "Coverage is grayscale arbitrary-MAXVAL coding, not complete baseline certification", "MAXVAL=1/2 require separate standard-derived tests because the official executable does not support them"],results=results)
    output.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    if args.record_output_examples:
        assert len(examples)==2
        receipts=[]
        for request,outgoing,decoded,item in examples.values():
            prefix=FIXTURES/"examples"/f"max1000-near{request['near']}"
            Path(str(prefix)+"-moonjls.jls").write_bytes(outgoing)
            Path(str(prefix)+"-moonjls-reference-decoded.pgm").write_bytes(decoded)
            receipts.append(dict(**item,files={p.name:sha256(p.read_bytes()) for p in prefix.parent.glob(prefix.name+"-*") if p.is_file()}))
        receipt=dict(recorded_at=datetime.now(timezone(timedelta(hours=8))).isoformat(),reference=reference_metadata(),
                     bridge_js_sha256=sha256(bridge.read_bytes()),verification="Live official reference decoder checked both MoonJLS output codestreams; maximal error <= NEAR",examples=receipts)
        (FIXTURES/"examples/output-verification.json").write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8")
    print(f"{report['result']}: {len(results)} independent incoming vectors"+(f" + {len(results)} live independent outgoing checks" if live else "; live outgoing reference unavailable (not claimed)"))

def annex_e(args):
    """Run licensed Annex E inputs privately through the actual file consumer."""
    image_dir=args.annex_dir.resolve()
    image_archive=image_dir.parent/"jlsimgV100.zip"
    assert image_archive.is_file(),"Keep the original jlsimgV100.zip beside the extracted image directory for provenance hashing"
    names=["T8C0E0.JLS","T8C0E3.JLS","T8C1E0.JLS","T8C1E3.JLS","T8C2E0.JLS","T8C2E3.JLS",
           "T8SSE0.JLS","T8SSE3.JLS","T8NDE0.JLS","T8NDE3.JLS","T16E0.JLS","T16E3.JLS"]
    assert all((image_dir/name).is_file() for name in names), "Extract official jlsimgV100.zip privately into --annex-dir first"
    cache=ROOT/"work/t87-validation";cache.mkdir(parents=True,exist_ok=True)
    results=[];nondefault_lossless=None
    with tempfile.TemporaryDirectory(prefix="annex-e-",dir=cache) as temporary:
        temporary=Path(temporary).resolve();assert temporary.is_relative_to(cache.resolve())
        for number,name in enumerate(names,1):
            near=3 if "E3" in name else 0
            sixteen=name.startswith("T16");subsampled="SS" in name
            original=read_pnm(image_dir/("TEST16.PGM" if sixteen else "TEST8.PPM"))
            components=original["components"]
            mode=0 if sixteen or "C0" in name else (2 if "C2" in name else 1)
            request=dict(width=original["width"],height=original["height"],components=components,
                         interleave=mode,near=near,preset=dict(maximum=original["maximum"]))
            source=image_dir/name;directory=temporary/name;directory.mkdir()
            item=dict(case=number,file=name,sha256=sha256(source.read_bytes()),near=near)
            try:
                if subsampled:
                    outputs=[directory/f"official-{c}.pgm" for c in range(3)]
                    run([program(request,False),source,*outputs],directory)
                    refs=[read_pnm(path) for path in outputs]
                    originals=[read_pnm(image_dir/f) for f in ("TEST8R.PGM","TEST8GR4.PGM","TEST8BS2.PGM")]
                    assert [(p["width"],p["height"]) for p in refs]==[(p["width"],p["height"]) for p in originals]
                    assert all(maximum_error(a["samples"],b["samples"])<=near for a,b in zip(refs,originals))
                    item["official_plane_dimensions"]=[[p["width"],p["height"]] for p in refs]
                elif "ND" in name:
                    # The supplied README calls these TEST8 RGB, but the actual
                    # codestreams are 128x128 single-component images. The
                    # corresponding source PGM is absent from the archive.
                    # Use the independent decoder's real output dimensions;
                    # compare E3 with the matching E0 lossless reconstruction.
                    expected_file=directory/"official.pgm"
                    run([program(request,False),source,expected_file],directory)
                    decoded=read_pnm(expected_file)
                    expected=decoded["samples"]
                    if near==0:nondefault_lossless=decoded
                    assert nondefault_lossless is not None
                    original=nondefault_lossless;components=original["components"]
                    assert maximum_error(original["samples"],expected)<=near,"Non-default E3 differs from independent E0 by more than NEAR"
                    item["source_provenance"]="Matching official E0 reconstruction; original source PGM absent, archive README dimensions disagree with codestream"
                else:
                    expected=decode(source.read_bytes(),request,directory/"official")
                    assert maximum_error(original["samples"],expected)<=near
                output=directory/"moonjls.pnm"
                result=subprocess.run(["node","scripts/moonjls.mjs","decode",str(source),str(output)],
                                      cwd=ROOT,capture_output=True,encoding="utf-8",timeout=60)
                if subsampled:
                    assert result.returncode!=0 and "unsupported JPEG-LS" in result.stderr and "subsampling" in result.stderr,result.stderr
                    assert not output.exists(), "Rejected Annex E input left a partial file"
                    item.update(result="KNOWN_GAP",reason="Subsampled component grids are explicitly Unsupported; not counted as conformance pass")
                else:
                    assert result.returncode==0,result.stderr
                    actual=read_pnm(output)
                    assert actual["samples"]==expected,"MoonJLS pixels differ from the official reference decoder"
                    assert (actual["width"],actual["height"],actual["components"],actual["maximum"])==(original["width"],original["height"],components,original["maximum"])
                    item.update(result="PASS",samples=len(expected),maximum_error=maximum_error(original["samples"],expected))
            except Exception as error:
                item.update(result="FAIL",reason=str(error))
            results.append(item)
            print(f"Annex E {number:02d} {name}: {item['result']}",flush=True)
    passed=sum(r["result"]=="PASS" for r in results);gaps=sum(r["result"]=="KNOWN_GAP" for r in results)
    failed=sum(r["result"]=="FAIL" for r in results)
    report=dict(reference=reference_metadata(),recorded_at=datetime.now(timezone(timedelta(hours=8))).isoformat(),
                source_archive="jlsimgV100.zip",source_archive_sha256=sha256(image_archive.read_bytes()),
                direction="decode-only",encoder_conformance="NOT_RUN",result="FAIL" if failed else ("PARTIAL" if gaps else "PASS"),
                cases=len(results),passed=passed,known_gaps=gaps,failed=failed,
                scope="Official Annex E inputs remain in ignored work/. Known gaps are not counted as pass or complete certification.",results=results)
    target=ROOT/"work/validation/t87-annex-e.json";target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    assert not failed, f"Annex E has {failed} unexpected failures; see {target}"
    print(f"Annex E: {passed} independently decoded PASS, {gaps} explicit KNOWN_GAP, {failed} FAIL; not complete conformance")


def main():
    global REFERENCE
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-dir",type=Path,default=REFERENCE)
    parser.add_argument("--annex-e",action="store_true",help="Also test all twelve official Annex E files using the file consumer")
    parser.add_argument("--annex-e-only",action="store_true",help="Test Annex E files without rerunning synthetic MAXVAL cases")
    parser.add_argument("--annex-dir",type=Path,default=ROOT/"work/standards/jlsimgV100")
    parser.add_argument("--generate-fixtures",action="store_true")
    parser.add_argument("--record-output-examples",action="store_true")
    parser.add_argument("--require-reference",action="store_true")
    parser.add_argument("--golden-only",action="store_true",help="Use committed official inputs even when Windows binaries are available")
    parser.add_argument("--quick",action="store_true")
    args=parser.parse_args();REFERENCE=args.reference_dir.resolve()
    if args.quick and (args.generate_fixtures or args.record_output_examples):parser.error("Quick checks cannot rewrite the complete evidence set")
    live=not args.golden_only and verified_reference()
    if (args.generate_fixtures or args.record_output_examples or args.require_reference or args.annex_e or args.annex_e_only) and not live:
        parser.error("This operation requires the original verified Windows T.87 reference binaries in --reference-dir")
    if args.annex_e_only:
        if args.generate_fixtures or args.record_output_examples or args.quick:parser.error("--annex-e-only cannot rewrite MAXVAL evidence or use --quick")
        annex_e(args);return
    requests=selected_cases()
    if args.quick:requests=requests[:12]
    if args.generate_fixtures:generate(requests)
    else:verify(args,requests,live)
    if args.annex_e:annex_e(args)

if __name__=="__main__":main()
