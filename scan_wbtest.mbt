///|
fn scan_test_image(
  width : Int32,
  height : Int32,
  bits : Int32,
  components : Int32,
  pattern : Int32,
) -> Image {
  let maximum = (1 << bits) - 1
  let samples = Array::makei(width * height * components, i => {
    let pixel = i / components
    let x = pixel % width
    let y = pixel / width
    let c = i % components
    match pattern {
      0 => 0
      1 => maximum
      2 => ((x * 13 + y * 29 + c * 67) * maximum / 255) & maximum
      3 => if (x + y + c) % 2 == 0 { maximum } else { 0 }
      4 =>
        if x < width / 2 {
          c * 3 % (maximum + 1)
        } else {
          maximum - c * 3 % (maximum + 1)
        }
      _ => ((i * 3331 + i * i % 65521 * 19 + 1493) ^ (i << 5)) & maximum
    }
  })
  { frame: { width, height, bits_per_sample: bits, components, }, samples, }
}

///|
test "scan codec lossless and bounded error across precision, runs and interleave" {
  for bits in [2, 4, 8, 12, 16] {
    let maximum = (1 << bits) - 1
    for count in [1, 2, 3, 4] {
      for pattern in 0..<6 {
        let image = scan_test_image(19, 11, bits, count, pattern)
        for near in [0, (1).min(maximum / 2), (3).min(maximum / 2)] {
          let preset = Preset::defaults(maximum, near)
          for mode in [None, Line, Sample] {
            if mode != None && count == 1 {
              continue
            }
            let decoded = try {
              let decoded = Array::make(image.samples.length(), 0)
              if mode == None {
                for component in 0..<count {
                  let wire = encode_scan(
                    image,
                    [component],
                    preset,
                    near,
                    None,
                    Limits::default(),
                  )
                  decode_scan(
                    wire[:],
                    0,
                    wire.length(),
                    image.frame,
                    [component],
                    preset,
                    near,
                    None,
                    decoded,
                    Limits::default(),
                  )
                }
              } else {
                let components = Array::makei(count, i => i)
                let wire = encode_scan(
                  image,
                  components,
                  preset,
                  near,
                  mode,
                  Limits::default(),
                )
                decode_scan(
                  wire[:],
                  0,
                  wire.length(),
                  image.frame,
                  components,
                  preset,
                  near,
                  mode,
                  decoded,
                  Limits::default(),
                )
              }
              decoded
            } catch {
              error =>
                abort(
                  "bits=\{bits} count=\{count} pattern=\{pattern} near=\{near} mode=\{mode.code()}: \{error.describe()}",
                )
            }
            for i in 0..<decoded.length() {
              assert_true((decoded[i] - image.samples[i]).abs() <= near)
            }
          }
        }
      }
    }
  }
}

///|
test "one-pixel and single-column rows retain prediction edges" {
  for width in [1, 2, 127] {
    for height in [1, 2, 65] {
      let image = scan_test_image(width, height, 16, 1, 5)
      let preset = Preset::defaults(65535, 0)
      let wire = encode_scan(image, [0], preset, 0, None, Limits::default())
      let decoded = Array::make(image.samples.length(), 0)
      decode_scan(
        wire[:],
        0,
        wire.length(),
        image.frame,
        [0],
        preset,
        0,
        None,
        decoded,
        Limits::default(),
      )
      assert_eq(decoded, image.samples)
    }
  }
}

///|
test "scan entropy truncation and output budgets fail without unchecked reads" {
  let image = scan_test_image(8, 7, 8, 1, 5)
  let preset = Preset::defaults(255, 0)
  let wire = encode_scan(image, [0], preset, 0, None, Limits::default())
  for length in 0..<wire.length() {
    let decoded = Array::make(image.samples.length(), 0)
    assert_true(
      try {
        decode_scan(
          wire[:length],
          0,
          length,
          image.frame,
          [0],
          preset,
          0,
          None,
          decoded,
          Limits::default(),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(
        encode_scan(image, [0], preset, 0, None, {
          ..Limits::default(),
          compressed_bytes: 1,
        }),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "custom MAXVAL and RESET obey reconstructed sample interval" {
  let maximum = 1023
  let image = {
    frame: { width: 17, height: 19, components: 1, bits_per_sample: 10, },
    samples: Array::makei(17 * 19, i => (i * 239 + i * i * 3) % (maximum + 1)),
  }
  for near in [0, 1, 9] {
    let preset = { ..Preset::defaults(maximum, near), reset: 17, }
    let wire = encode_scan(image, [0], preset, near, None, Limits::default())
    let decoded = Array::make(image.samples.length(), 0)
    decode_scan(
      wire[:],
      0,
      wire.length(),
      image.frame,
      [0],
      preset,
      near,
      None,
      decoded,
      Limits::default(),
    )
    for i in 0..<decoded.length() {
      assert_true(decoded[i] >= 0 && decoded[i] <= maximum)
      assert_true((decoded[i] - image.samples[i]).abs() <= near)
    }
  }
}
