///|
test "all MAXVAL domains reconstruct within their own RANGE for every interleave" {
  for
    maximum in [
      1, 2, 3, 7, 31, 100, 127, 128, 255, 256, 511, 1000, 1023, 1024, 4095, 4096,
      32768, 65534, 65535,
    ] {
    let bits = ceil_log2(maximum + 1).max(2)
    for count in [1, 2, 3, 4] {
      let image : Image = {
        frame: {
          width: 13,
          height: 7,
          bits_per_sample: bits,
          components: count,
        },
        samples: Array::makei(91 * count, i => {
          if i % 8 == 0 {
            maximum
          } else if i % 8 == 1 {
            0
          } else {
            (i * 331 + i * i * 7) % (maximum + 1)
          }
        }),
      }
      let modes : Array[Interleave] = if count == 1 {
        [None]
      } else {
        [None, Line, Sample]
      }
      for mode in modes {
        for
          near in [
            0,
            (1).min(maximum / 2),
            (3).min(maximum / 2),
            (255).min(maximum / 2),
          ] {
          let options = {
            near,
            interleave: mode,
            preset: { ..Preset::automatic(), maximum, },
          }
          let bytes = encode(image, options~)
          let info = inspect(bytes[:])
          for scan in info.scans {
            assert_eq(scan.preset.maximum, maximum)
          }
          let restored = decode(bytes[:])
          ignore(verify_near(image, restored, near))
          for value in restored.samples {
            assert_true(value >= 0 && value <= maximum)
          }
        }
      }
    }
  }
}

///|
test "MAXVAL and precision are distinct including a sixteen-bit container for 1000" {
  let image : Image = {
    frame: { width: 5, height: 2, bits_per_sample: 16, components: 1, },
    samples: [0, 1, 255, 256, 1000, 999, 513, 17, 500, 47],
  }
  let options = {
    ..EncodeOptions::default(),
    preset: { ..Preset::automatic(), maximum: 1000, },
  }
  let bytes = encode(image, options~)
  let info = inspect(bytes[:])
  assert_eq(info.frame.bits_per_sample, 16)
  assert_eq(info.scans[0].preset.maximum, 1000)
  assert_eq(decode(bytes[:]), image)
  assert_eq(CodingTraits::new(info.scans[0].preset, 0).limit, 40)
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
  assert_eq(out.to_bytes(), bytes)
  assert_eq(decode(encode_restarted(image, 1, options~)[:]), image)
}

///|
test "MAXVAL one and two have normative short Golomb vectors" {
  // T.87 A.2/A.7: RANGE=2 or 3, initial A=2,N=1 and RItype=1.
  // One zero run followed by error -1 gives bits 10 + 10, padded to A0.
  // For MAXVAL=2, positive error +1 instead gives 10 + 11, padded to B0.
  for
    (maximum, values, expected) in [
      (1, [0, 1], b"\xa0"),
      (2, [0, 2], b"\xa0"),
      (2, [0, 1], b"\xb0"),
    ] {
    let image : Image = {
      frame: { width: 2, height: 1, bits_per_sample: 2, components: 1, },
      samples: values,
    }
    let bytes = encode(image, options={
      ..EncodeOptions::default(),
      preset: { ..Preset::automatic(), maximum, },
    })
    let scan = inspect(bytes[:]).scans[0]
    assert_eq(bytes[scan.entropy_offset:scan.entropy_end], expected[:])
    assert_eq(decode(bytes[:]), image)
    let traits = CodingTraits::new(scan.preset, 0)
    assert_eq(traits.limit, 20)
    assert_eq(traits.qbpp, if maximum == 1 { 1 } else { 2 })
  }
}

///|
test "MAXVAL bounds, NEAR and pixel values are validated independently" {
  for
    preset in [
      { ..Preset::automatic(), maximum: -1, },
      { ..Preset::automatic(), maximum: 4, },
      { ..Preset::automatic(), maximum: 65536, },
    ] {
    expect_jls_error(() => ignore(preset.resolve(2, 0)))
  }
  expect_jls_error(() => {
    ignore(({ ..Preset::automatic(), maximum: 1, } : Preset).resolve(2, 1))
  })
  let image : Image = {
    frame: { width: 1, height: 1, bits_per_sample: 10, components: 1, },
    samples: [1001],
  }
  expect_jls_error(() => {
    ignore(
      encode(image, options={
        ..EncodeOptions::default(),
        preset: { ..Preset::automatic(), maximum: 1000, },
      }),
    )
  })
}
