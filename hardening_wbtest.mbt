///|
test "packed layouts reject overflowing row byte counts before allocation" {
  let frame : Frame = {
    width: 1073741824,
    height: 1,
    bits_per_sample: 16,
    components: 1,
  }
  let limits = {
    ..Limits::default(),
    pixels: 2147483647,
    samples: 2147483647,
    compressed_bytes: 2147483647,
  }
  for order in [Interleaved, Planar] {
    expect_jls_error(() => {
      ignore(
        frame.packed_size(PixelLayout::tight(storage=U16Big, order~), limits~),
      )
    })
  }
}

///|
test "encoder marker budgets reject before pull callbacks or push sinks run" {
  let image = integration_image(3, 2, 8, 1)
  let limits = { ..Limits::default(), segments: 2, }
  expect_jls_error(() => ignore(encode(image, limits~)))
  let mut calls = 0
  expect_jls_error(() => {
    ignore(
      encode_rows(
        image.frame,
        (y, _) => {
          calls += 1
          image.row(y)
        },
        limits~,
      ),
    )
  })
  assert_eq(calls, 0)
  expect_jls_error(() => {
    ignore(RowEncoder::new(image.frame, _ => calls += 1, limits~))
  })
  assert_eq(calls, 0)
  let restarted = integration_image(3, 5, 8, 1)
  expect_jls_error(() => {
    ignore(
      encode_restarted(restarted, 1, limits={
        ..Limits::default(),
        segments: 5,
      }),
    )
  })
}

///|
test "restart markers count toward inspection and framing segment budgets" {
  let image = integration_image(3, 5, 8, 1)
  let bytes = encode_restarted(image, 1)
  let limits = { ..Limits::default(), segments: 4, }
  expect_jls_error(() => ignore(inspect(bytes[:], limits~)))
  let framer = CodestreamFramer::new(limits~)
  expect_jls_error(() => ignore(framer.feed(bytes[:])))
}

///|
test "HP output honors both segment and metadata payload budgets" {
  let image = integration_image(3, 2, 8, 3)
  expect_jls_error(() => {
    ignore(
      encode_transformed(image, Hp1, limits={
        ..Limits::default(),
        metadata_bytes: 4,
      }),
    )
  })
  expect_jls_error(() => {
    ignore(
      encode_transformed(image, Hp1, limits={
        ..Limits::default(),
        segments: 3,
      }),
    )
  })
}

///|
test "PNM readers and writers agree on the full header budget including separators" {
  for header in [b"P5\n1 1\n255\n", b"P5\r\n1 1\r\n255\r\n"] {
    let out = @buffer.Buffer::Buffer()
    out.write_bytes(header[:])
    out.write_byte(b'\x23')
    let data = out.to_bytes()
    let limits = { ..Limits::default(), metadata_bytes: header.length() - 1, }
    expect_jls_error(() => ignore(parse_pnm(data[:], limits~)))
    expect_jls_error(() => {
      ignore(PnmSource::open(ByteSource::from_bytes(data), limits~))
    })
    assert_eq(
      parse_pnm(data[:], limits={ ..limits, metadata_bytes: header.length(), }).image.samples,
      [35],
    )
  }
  let mut emitted = 0
  expect_jls_error(() => {
    ignore(
      write_pnm_rows(
        image_test_gray(8, [1]).frame,
        _ => [1],
        bytes => emitted += bytes.length(),
        limits={ ..Limits::default(), metadata_bytes: 0, },
      ),
    )
  })
  assert_eq(emitted, 0)
}

///|
test "PNM exports wider than SOF16 can be reopened by either raster reader" {
  let image : Image = {
    frame: { width: 65536, height: 1, bits_per_sample: 8, components: 1, },
    samples: Array::make(65536, 35),
  }
  let bytes = encode_pnm(image)
  assert_eq(parse_pnm(bytes[:]).image, image)
  let source = PnmSource::open(ByteSource::from_bytes(bytes))
  assert_eq(source.frame(), image.frame)
  assert_eq(source.row(0), image.samples)
}

///|
test "source PNM validates raw byte budgets and row byte overflow without reading raster" {
  let bytes = b"P5\n1 1\n255\n\x00"
  expect_jls_error(() => {
    ignore(
      PnmSource::open(ByteSource::from_bytes(bytes), limits={
        ..Limits::default(),
        compressed_bytes: 3,
      }),
    )
  })
  let header = b"P5\n1073741824 1\n65535\n"
  let source = ByteSource::new(header.length().to_uint64() + 2147483648UL, (
    offset,
    length,
  ) => {
    let at = offset.to_int()
    Bytes::from_array(
      Array::makei(length, i => {
        if at + i < header.length() {
          header[at + i]
        } else {
          b'\x00'
        }
      }),
    )
  })
  expect_jls_error(() => {
    ignore(
      PnmSource::open(source, limits={
        ..Limits::default(),
        pixels: 2147483647,
        samples: 2147483647,
        compressed_bytes: 2147483647,
      }),
    )
  })
}

///|
test "info JSON preserves an explicit expanded limit for SPIFF metadata" {
  let frame : Frame = {
    width: 4096,
    height: 4097,
    bits_per_sample: 8,
    components: 1,
  }
  let limits = { ..Limits::default(), pixels: 20000000, samples: 20000000, }
  let out = @buffer.Buffer::Buffer()
  out.write_bytes(b"\xff\xd8"[:])
  append_segment(
    out,
    0xE8,
    spiff_bytes(SpiffHeader::default(frame))[:],
    limits.compressed_bytes,
  )
  append_segment(
    out,
    0xE8,
    b"\x00\x00\x00\x01\xff\xd8"[:],
    limits.compressed_bytes,
  )
  write_frame(out, frame, limits)
  write_scan_header(out, [0], EncodeOptions::default(), limits)
  out.write_bytes(b"\x80\xff\xd9"[:])
  let info = inspect(out.to_bytes()[:], limits~)
  // This stream is inspected only: no large image allocation or entropy decode.
  assert_true(info.spiff_header(limits~) is Some(_))
  ignore(info.to_json(limits~))
}

///|
test "exact marker budgets remain usable for presets, planar scans and restarts" {
  let gray = integration_image(3, 5, 8, 1)
  let color = integration_image(3, 5, 8, 3)
  let cases : Array[(Bytes, Limits)] = [
    (
      encode(gray, limits={ ..Limits::default(), segments: 3, }),
      { ..Limits::default(), segments: 3, },
    ),
    (
      encode(
        gray,
        options={
          ..EncodeOptions::default(),
          preset: { ..Preset::automatic(), reset: 7, },
        },
        limits={ ..Limits::default(), segments: 4, },
      ),
      { ..Limits::default(), segments: 4, },
    ),
    (
      encode(color, limits={ ..Limits::default(), segments: 5, }),
      { ..Limits::default(), segments: 5, },
    ),
    (
      encode_restarted(color, 1, limits={ ..Limits::default(), segments: 18, }),
      { ..Limits::default(), segments: 18, },
    ),
    (
      encode_transformed(color, Hp2, limits={
        ..Limits::default(),
        segments: 4,
        metadata_bytes: 5,
      }),
      { ..Limits::default(), segments: 4, metadata_bytes: 5, },
    ),
  ]
  for (bytes, limits) in cases {
    let decoded = decode(bytes[:], limits~)
    assert_eq(decoded, if decoded.frame.components == 1 { gray } else { color })
  }
}

///|
test "header budgets stop long PNM comments and missing ASCII separators" {
  let buffer = @buffer.Buffer::Buffer()
  buffer.write_bytes(b"P5\n#"[:])
  for _ in 0..<1000 {
    buffer.write_byte(b'x')
  }
  buffer.write_bytes(b"\n1 1\n255\n\x00"[:])
  expect_jls_error(() => {
    ignore(
      parse_pnm(buffer.to_bytes()[:], limits={
        ..Limits::default(),
        metadata_bytes: 16,
      }),
    )
  })
  expect_jls_error(() => {
    ignore(parse_pnm(b"P2\n1 1\n3#missing separator\n0"[:]))
  })
}

///|
test "every single-bit mutation is bounded or returns a typed codec error" {
  let gray = integration_image(7, 3, 8, 1)
  let color = integration_image(5, 3, 12, 3)
  let rgb = integration_image(5, 3, 8, 3)
  let seeds = [
    encode(gray),
    encode(color, options={ ..EncodeOptions::default(), interleave: Sample, }),
    encode_restarted(color, 1),
    with_spiff(encode_transformed(rgb, Hp1)[:], SpiffHeader::default(rgb.frame)),
  ]
  let limits = {
    pixels: 128,
    samples: 512,
    compressed_bytes: 4096,
    metadata_bytes: 512,
    segments: 32,
  }
  for seed in seeds {
    for at in 0..<seed.length() {
      for bit in 0..<8 {
        let mutated = seed.to_array()
        mutated[at] = (mutated[at].to_int() ^ (1 << bit)).to_byte()
        let bytes = Bytes::from_array(mutated)
        let result = Some(decode(bytes[:], limits~)) catch { _ => None }
        if result is Some(image) {
          image.validate(limits~)
          assert_true(image.samples.length() <= limits.samples)
        }
      }
    }
  }
}
