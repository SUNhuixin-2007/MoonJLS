///|
fn integration_image(
  w : Int32,
  h : Int32,
  bits : Int32,
  components : Int32,
) -> Image {
  {
    frame: { width: w, height: h, bits_per_sample: bits, components, },
    samples: Array::makei(w * h * components, i => {
      (i * 331 + i * i * 7) & ((1 << bits) - 1)
    }),
  }
}

///|
fn expect_jls_error(action : () -> Unit raise JlsError) -> Unit raise {
  assert_true(
    try {
      action()
      false
    } catch {
      _ => true
    },
  )
}

///|
test "row pull and push encoders agree with complete-image coding" {
  for components in [1, 2, 3, 4] {
    let image = integration_image(23, 9, 12, components)
    let modes : Array[Interleave] = if components == 1 {
      [None]
    } else {
      [None, Line, Sample]
    }
    for mode in modes {
      for near in [0, 3] {
        let options = { ..EncodeOptions::default(), near, interleave: mode, }
        let expected = encode(image, options~)
        let pulled = encode_rows(
          image.frame,
          (y, selected) => {
            Array::makei(image.frame.width * selected.length(), i => {
              image.samples[(y * image.frame.width + i / selected.length()) *
              components +
              selected[i % selected.length()]]
            })
          },
          options~,
        )
        assert_eq(pulled, expected)
        if components == 1 || mode != None {
          let out = @buffer.Buffer::Buffer()
          let encoder = RowEncoder::new(
            image.frame,
            b => out.write_bytes(b[:]),
            options~,
          )
          for y in 0..<image.frame.height {
            encoder.push(image.row(y))
          }
          encoder.finish()
          assert_eq(encoder.rows_written(), image.frame.height)
          assert_eq(encoder.bytes_written(), expected.length())
          assert_eq(out.to_bytes(), expected)
        }
      }
    }
  }
}

///|
test "row decoder callbacks retain owned rows including planar scans" {
  let image = integration_image(13, 7, 8, 3)
  for mode in [None, Line, Sample] {
    let wire = encode(image, options={
      ..EncodeOptions::default(),
      interleave: mode,
    })
    let restored = Array::make(image.samples.length(), 0)
    let rows : Array[Array[Int32]] = []
    let saved : Array[Array[Int32]] = []
    ignore(
      decode_rows(wire[:], (y, selected, row) => {
        rows.push(row)
        saved.push(row.copy())
        for x in 0..<image.frame.width {
          for c in 0..<selected.length() {
            restored[(y * image.frame.width + x) * 3 + selected[c]] = row[x *
              selected.length() +
              c]
          }
        }
      }),
    )
    assert_eq(rows, saved)
    assert_eq(restored, image.samples)
  }
}

///|
test "push encoder poisons incomplete or rejected streams and propagates sink errors" {
  let image = integration_image(3, 2, 8, 1)
  let encoder = RowEncoder::new(image.frame, _ => ())
  encoder.push(image.row(0))
  expect_jls_error(() => encoder.finish())
  expect_jls_error(() => encoder.push(image.row(1)))
  let bad = RowEncoder::new(image.frame, _ => ())
  expect_jls_error(() => bad.push([256, 0, 0]))
  expect_jls_error(() => bad.push(image.row(0)))
  let mut calls = 0
  let failing = RowEncoder::new(image.frame, _ => {
    calls += 1
    if calls > 1 {
      raise Invalid(0, "test sink failure")
    }
  })
  expect_jls_error(() => {
    failing.push(image.row(0))
    failing.push(image.row(1))
    failing.finish()
  })
  expect_jls_error(() => failing.finish())
}

///|
test "restart intervals preserve reconstruction and reject wrong sequence numbers" {
  for components in [1, 3, 4] {
    let image = integration_image(17, 11, 10, components)
    let modes : Array[Interleave] = if components == 1 {
      [None]
    } else {
      [None, Line, Sample]
    }
    for mode in modes {
      for near in [0, 2] {
        for interval in [1, 3, 20] {
          let wire = encode_restarted(image, interval, options={
            ..EncodeOptions::default(),
            near,
            interleave: mode,
          })
          assert_eq(inspect(wire[:]).scans[0].restart_interval, interval)
          ignore(verify_near(image, decode(wire[:]), near))
          if interval == 1 {
            let bytes = wire.to_array()
            let mut changed = false
            for i in 1..<bytes.length() {
              if bytes[i - 1] == b'\xff' && bytes[i] == b'\xd0' {
                bytes[i] = b'\xd1'
                changed = true
                break
              }
            }
            assert_true(changed)
            expect_jls_error(() => ignore(decode(Bytes::from_array(bytes)[:])))
          }
        }
      }
    }
  }
}

///|
test "SPIFF and annotation edits preserve essential HP transforms" {
  let image = integration_image(11, 5, 16, 3)
  let raw = encode_transformed(image, Hp3)
  let annotated = with_metadata(raw[:], [
    { marker: 0xFE, offset: 0, data: b"synthetic image", },
  ])
  let header = {
    ..SpiffHeader::default(image.frame),
    resolution_units: 1,
    vertical_resolution: 300U,
    horizontal_resolution: 300U,
  }
  let wrapped = with_spiff(annotated[:], header)
  assert_eq(inspect(wrapped[:]).spiff_header(), Some(header))
  assert_eq(decode(wrapped[:]), image)
  assert_eq(decode(strip_metadata(wrapped[:])[:]), image)
  assert_eq(inspect(strip_metadata(wrapped[:])[:]).color_transform(), Hp3)
  let bytes = wrapped.to_array()
  bytes[4 + 2 + 17] = b'\x0a'
  expect_jls_error(() => ignore(decode(Bytes::from_array(bytes)[:])))
  expect_jls_error(() => {
    ignore(
      with_metadata(raw[:], [{ marker: 0xE8, offset: 0, data: b"mrfx\x01", }]),
    )
  })
}

///|
test "codestream framing survives every boundary and concatenation" {
  let image = integration_image(7, 5, 8, 3)
  let first = with_spiff(
    encode(image, options={ ..EncodeOptions::default(), interleave: Sample, })[:],
    SpiffHeader::default(image.frame),
  )
  let second = encode_restarted(image, 1, options={
    ..EncodeOptions::default(),
    interleave: Line,
  })
  let combined = @buffer.Buffer::Buffer()
  combined.write_bytes(first[:])
  combined.write_bytes(second[:])
  let bytes = combined.to_bytes()
  for size in 1..<=bytes.length() {
    let framer = CodestreamFramer::new()
    let result : Array[Bytes] = []
    for at = 0; at < bytes.length(); at = at + size {
      result.append(framer.feed(bytes[at:(at + size).min(bytes.length())]))
    }
    framer.finish()
    assert_eq(result, [first, second])
    assert_eq(framer.image_count(), 2UL)
    assert_eq(framer.input_bytes(), bytes.length().to_uint64())
    assert_eq(framer.buffered_bytes(), 0)
  }
  let broken = CodestreamFramer::new()
  ignore(broken.feed(first[:first.length() - 1]))
  expect_jls_error(() => broken.finish())
  expect_jls_error(() => ignore(broken.feed(first[:])))
  broken.reset()
  assert_eq(broken.feed(first[:]), [first])
  broken.finish()
}

///|
test "extended dimensions and custom MAXVAL presets are real codestream parameters" {
  let wide : Image = {
    frame: { width: 65536, height: 1, bits_per_sample: 8, components: 1, },
    samples: Array::make(65536, 17),
  }
  let wire = encode(wide)
  assert_eq(inspect(wire[:]).frame, wide.frame)
  assert_eq(decode(wire[:]), wide)
  let small = {
    frame: { width: 7, height: 3, bits_per_sample: 10, components: 1, },
    samples: Array::makei(21, i => i * 47 % 1001),
  }
  for near in [0, 3] {
    let preset = { ..Preset::automatic(), maximum: 1023, reset: 7, }
    let bytes = encode(small, options={
      ..EncodeOptions::default(),
      near,
      preset,
    })
    assert_eq(inspect(bytes[:]).scans[0].preset.maximum, 1023)
    assert_eq(inspect(bytes[:]).scans[0].preset.reset, 7)
    ignore(verify_near(small, decode(bytes[:]), near))
  }
}

///|
test "PAM handles alpha, big endian, binary separators and incremental writes" {
  for components in [1, 2, 3, 4] {
    for bits in [2, 8, 10, 16] {
      let image = integration_image(5, 3, bits, components)
      let bytes = encode_pam(image)
      let parsed = parse_pam(bytes[:])
      assert_eq(parsed.image, image)
      assert_eq(parsed.encode(), bytes)
      let out = @buffer.Buffer::Buffer()
      let length = write_pam_rows(image.frame, y => image.row(y), b => {
        out.write_bytes(b[:])
      })
      assert_eq(length, bytes.length().to_uint64())
      assert_eq(out.to_bytes(), bytes)
    }
  }
  assert_eq(
    parse_pam(
      b"P7\r\n# c\r\nWIDTH 2\r\nHEIGHT 1\r\nDEPTH 2\r\nMAXVAL 255\r\nTUPLTYPE GRAYSCALE_ALPHA\r\nENDHDR\r\n\x0a\x23\x20\xff"[:],
    ).image.samples,
    [10, 35, 32, 255],
  )
  for
    bad in [
      b"P7\nWIDTH 1\nWIDTH 1\nENDHDR\n", b"P7\nWIDTH 1\nHEIGHT 1\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB\nENDHDR\n\x00\x00\x00\x00",
      b"P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 3\nENDHDR\n\xff",
    ] {
    expect_jls_error(() => ignore(parse_pam(bad[:])))
  }
}

///|
test "file byte sources preserve UInt64 offsets and reject short reads" {
  let bytes = b"P6\n2 1\n1023\n\x00\x0a\x00\x23\x03\xe8\x00\x20\x01\x00\x00\x00"
  let base = 4294967301UL
  let source = ByteSource::new(base + bytes.length().to_uint64(), (
    offset,
    length,
  ) => {
    guard offset >= base else {
      raise Invalid(0, "unexpected header-prefix read")
    }
    let at = (offset - base).to_int()
    bytes[at:at + length].to_owned()
  })
  let pnm = PnmSource::open(source, start=base)
  assert_eq(pnm.frame().components, 3)
  assert_eq(pnm.maximum(), 1023)
  assert_true(pnm.raster_offset() > base)
  assert_eq(pnm.row(0), [10, 35, 1000, 32, 256, 0])
  assert_eq(pnm.row(0, components=[2, 0]), [1000, 10, 0, 32])
  assert_eq(
    decode(
      pnm.encode(options={ ..EncodeOptions::default(), interleave: Line, })[:],
    ).samples,
    pnm.row(0),
  )
  let short = ByteSource::new(2UL, (_, _) => b"")
  expect_jls_error(() => ignore(short.read(0UL, 1)))
  expect_jls_error(() => ignore(source.slice(base, 999UL)))
}

///|
test "ROI selection keeps requested channel order for all scan layouts" {
  let image = integration_image(9, 7, 12, 3)
  let region : Region = { x: 2, y: 3, width: 4, height: 2, }
  for mode in [None, Line, Sample] {
    let bytes = encode_restarted(image, 2, options={
      ..EncodeOptions::default(),
      interleave: mode,
    })
    let cropped = image.crop(2, 3, 4, 2)
    let expected = merge_planes([cropped.plane(2), cropped.plane(0)][:])
    assert_eq(decode_region(bytes[:], region, components=[2, 0]), expected)
  }
  assert_eq(Region::from_json(region.to_json(), image.frame), region)
  let tiles = tile_regions(image.frame, 4, 3)
  assert_eq(tiles.length(), 9)
  let mut area = 0
  for tile in tiles {
    tile.validate(image.frame)
    area += tile.width * tile.height
  }
  assert_eq(area, 63)
}

///|
test "histogram summaries, quantiles and batch arithmetic are atomic" {
  let a = SampleHistogram::new(8, 1, maximum_samples=10)
  a.push([0, 0, 10, 10][:])
  let b = SampleHistogram::new(8, 1)
  b.push([20, 20][:])
  a.merge(b)
  assert_eq(a.sample_count(), 6)
  assert_eq(a.summary(0).mean, 10.0)
  assert_eq(a.summary(0).distinct, 3)
  assert_eq(a.quantile(0, 0.5), 10)
  a.subtract(b)
  assert_eq(a.summary(0).variance, 25.0)
  expect_jls_error(() => a.subtract(b))
  assert_eq(a.sample_count(), 4)
  expect_jls_error(() => a.push([1, 256][:]))
  assert_eq(a.count(0, 1), 0)
  a.merge(a)
  assert_eq(a.sample_count(), 8)
  a.subtract(a)
  assert_eq(a.sample_count(), 0)
}

///|
test "rate control measures bounded candidates and returns only fitting encodings" {
  let image = integration_image(13, 5, 8, 1)
  let curve = rate_curve(image, [0, 1, 3], [None])
  assert_eq(curve.length(), 3)
  for point in curve {
    assert_true(point.maximum_error <= point.near)
  }
  assert_eq(encode_to_budget(image, 0, [0, 1], [None]), None)
  let choice = encode_to_budget(image, 10000, [0, 1, 3], [None]).unwrap()
  assert_eq(choice.attempts, 3)
  assert_eq(choice.point.near, 0)
  assert_eq(decode(choice.codestream[:]), image)
  expect_jls_error(() => ignore(rate_curve(image, [0, 0], [None])))
  expect_jls_error(() => {
    ignore(rate_curve(image, [0, 1], [None], maximum_attempts=1))
  })
  expect_jls_error(() => {
    ignore(rate_curve(image, [0], [None], work_sample_budget=1UL))
  })
}

///|
test "complete decoder rejects all truncations, trailing bytes and small budgets" {
  let image = integration_image(11, 5, 12, 3)
  let bytes = with_spiff(
    encode(image, options={ ..EncodeOptions::default(), interleave: Sample, })[:],
    SpiffHeader::default(image.frame),
  )
  for end in 0..<bytes.length() {
    expect_jls_error(() => ignore(decode(bytes[:end])))
  }
  let extra = @buffer.Buffer::Buffer()
  extra.write_bytes(bytes[:])
  extra.write_byte(b'\x00')
  expect_jls_error(() => ignore(decode(extra.to_bytes()[:])))
  expect_jls_error(() => {
    ignore(decode(bytes[:], limits={ ..Limits::default(), samples: 1, }))
  })
  expect_jls_error(() => {
    ignore(
      decode(bytes[:], limits={
        ..Limits::default(),
        compressed_bytes: bytes.length() - 1,
      }),
    )
  })
}

///|
test "reusable row copies preserve selection and reject invalid calls atomically" {
  let image = integration_image(5, 2, 8, 3)
  let row = Array::make(10, -1)
  image.copy_row_into(1, row, components=[2, 0])
  let expected = merge_planes([image.plane(2), image.plane(0)][:])
  assert_eq(row, expected.row(1))
  let before = row.copy()
  expect_jls_error(() => image.copy_row_into(2, row, components=[2, 0]))
  expect_jls_error(() => image.copy_row_into(1, row, components=[0, 0]))
  assert_eq(row, before)
}

///|
test "non-full-range MAXVAL is explicitly outside the interoperable codec profile" {
  let image = integration_image(3, 2, 10, 1)
  expect_jls_error(() => {
    ignore(
      encode(image, options={
        ..EncodeOptions::default(),
        preset: { ..Preset::automatic(), maximum: 1000, },
      }),
    )
  })
  let pnm = PnmSource::open(ByteSource::from_bytes(b"P5\n1 1\n1000\n\x00\x01"))
  assert_eq(pnm.row(0), [1])
  expect_jls_error(() => ignore(pnm.encode()))
}

///|
test "row copy permits in-place channel reordering without overwriting its source" {
  let image : Image = {
    frame: { width: 2, height: 1, bits_per_sample: 8, components: 3, },
    samples: [1, 2, 3, 10, 20, 30],
  }
  image.copy_row_into(0, image.samples, components=[2, 1, 0])
  assert_eq(image.samples, [3, 2, 1, 30, 20, 10])
  let broken : Image = { ..image, samples: [1, 2, 999, 10, 20, 30], }
  let destination = Array::make(6, -1)
  expect_jls_error(() => broken.copy_row_into(0, destination))
  assert_eq(destination, [-1, -1, -1, -1, -1, -1])
}

///|
test "sample custom RESET has explicit local reconstruction evidence" {
  let image = integration_image(19, 13, 16, 3)
  let options = {
    ..EncodeOptions::default(),
    interleave: Sample,
    preset: {
      ..Preset::automatic(),
      reset: 13,
      threshold1: 100,
      threshold2: 400,
      threshold3: 1000,
    },
  }
  let wire = encode(image, options~)
  assert_eq(decode(wire[:]), image)
  let out = @buffer.Buffer::Buffer()
  let encoder = RowEncoder::new(
    image.frame,
    b => out.write_bytes(b[:]),
    options~,
  )
  for y in 0..<image.frame.height {
    encoder.push(image.row(y))
  }
  encoder.finish()
  assert_eq(out.to_bytes(), wire)
}
