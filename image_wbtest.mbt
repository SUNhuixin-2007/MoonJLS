///|
fn image_test_gray(bits : Int32, values : Array[Int32]) -> Image {
  {
    frame: {
      width: values.length(),
      height: 1,
      bits_per_sample: bits,
      components: 1,
    },
    samples: values,
  }
}

///|
test "binary PNM preserves first whitespace or hash pixel and exact MAXVAL" {
  let out = @buffer.Buffer::Buffer()
  out.write_bytes(b"P5\n6 1\n255\n"[:])
  out.write_bytes(b"\x0a\x20\x23\x00\xff\x0d"[:])
  let parsed = parse_pnm(out.to_bytes()[:])
  assert_eq(parsed.image.samples, [10, 32, 35, 0, 255, 13])
  assert_eq(parsed.maximum, 255)
  assert_eq(parsed.encode(), out.to_bytes())
  let crlf = parse_pnm(b"P5\r\n1 1\r\n255\r\n\x23"[:])
  assert_eq(crlf.image.samples, [35])
  let bilevel = parse_pnm(b"P2\n2 1\n1\n0 1"[:])
  assert_eq(bilevel.image.frame.bits_per_sample, 2)
  assert_eq(bilevel.maximum, 1)
}

///|
test "PNM ASCII comments, RGB and big-endian sixteen-bit samples" {
  let image = {
    frame: { width: 2, height: 2, bits_per_sample: 16, components: 3, },
    samples: [0, 1, 255, 256, 257, 65535, 40000, 32768, 12345, 42, 43, 44],
  }
  for ascii in [false, true] {
    let encoded = encode_pnm(image, ascii~)
    assert_eq(parse_pnm(encoded[:]).image, image)
  }
  let parsed = parse_pnm(
    b"P3 # image\n2 1 # size\n15\n0 1 # red\n2 3 4 15 # end\n"[:],
  )
  assert_eq(parsed.image.samples, [0, 1, 2, 3, 4, 15])
  assert_eq(parsed.image.frame.bits_per_sample, 4)
  let custom = { image: image_test_gray(10, [0, 1023, 1000]), maximum: 1023, }
  let binary = custom.encode()
  assert_eq(binary[binary.length() - 6:], b"\x00\x00\x03\xff\x03\xe8"[:])
  assert_eq(parse_pnm(binary[:]), custom)
}

///|
test "PNM rejects malformed numeric headers, counts, samples and budgets" {
  for
    input in [
      b"", b"P", b"P5", b"P1\n1 1\n0", b"P51 1\n255\n\x00", b"P5\n0 1\n255\n", b"P5\n1 -1\n255\n\x00",
      b"P5\n1 1\n0\n\x00", b"P5\n65536 1\n255\n", b"P5\n1 1\n65536\n\x00", b"P5\n2 1\n255\n\x00",
      b"P5\n1 1\n15\n\xff", b"P5\n1 1\n255\n\x00\n", b"P5\n1 1\n255#x\n\x00", b"P2\n1 1\n3\n4",
      b"P2\n1 1\n3\n0 1", b"P2\n1 1\n3\n",
    ] {
    assert_true(
      try {
        ignore(parse_pnm(input[:]))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(
        parse_pnm(b"P5\n1 1\n255\n\x00"[:], limits={
          ..Limits::default(),
          metadata_bytes: 4,
        }),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        encode_pnm(image_test_gray(8, [1]), limits={
          ..Limits::default(),
          compressed_bytes: 3,
        }),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "packed image layouts preserve unsigned samples across stride and endian choices" {
  let image = {
    frame: { width: 2, height: 2, bits_per_sample: 16, components: 3, },
    samples: [1, 257, 65535, 256, 30000, 42, 8, 9, 10, 65534, 32768, 50000],
  }
  for order in [Interleaved, Planar] {
    for storage in [U16Big, U16Little] {
      let row_stride = if order == Interleaved { 15 } else { 7 }
      let layout = {
        order,
        storage,
        row_stride,
        plane_stride: if order == Planar {
          row_stride * 2 + 5
        } else {
          0
        },
      }
      let bytes = image.to_packed(layout~)
      assert_eq(bytes.length(), image.frame.packed_size(layout))
      assert_eq(Image::from_packed(image.frame, bytes[:], layout~), image)
      let extra = @buffer.Buffer::Buffer()
      extra.write_bytes(bytes[:])
      extra.write_bytes(b"\x00\x00\x00"[:])
      assert_eq(
        Image::from_packed(image.frame, extra.to_bytes()[:], layout~),
        image,
      )
    }
  }
  assert_eq(
    image_test_gray(16, [256, 65535]).to_packed(
      layout=PixelLayout::tight(storage=U16Big),
    ),
    b"\x01\x00\xff\xff",
  )
  assert_eq(
    image_test_gray(16, [256, 65535]).to_packed(
      layout=PixelLayout::tight(storage=U16Little),
    ),
    b"\x00\x01\xff\xff",
  )
}

///|
test "packed buffers reject overlap, insufficient precision and boundary overflow" {
  let image = image_test_gray(16, [65535, 1])
  assert_true(
    try {
      ignore(image.to_packed())
      false
    } catch {
      _ => true
    },
  )
  for
    layout in [
      { order: Interleaved, storage: U16Big, row_stride: 3, plane_stride: 0, },
      { order: Interleaved, storage: U16Big, row_stride: -1, plane_stride: 0, },
      { order: Interleaved, storage: U16Big, row_stride: 4, plane_stride: 4, },
      { order: Planar, storage: U16Big, row_stride: 4, plane_stride: 3, },
      {
        order: Planar,
        storage: U16Big,
        row_stride: 2147483647,
        plane_stride: 2147483647,
      },
    ] {
    assert_true(
      try {
        ignore(image.to_packed(layout~))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(
        Image::from_packed(
          image.frame,
          b"\xff"[:],
          layout=PixelLayout::tight(storage=U16Big),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        Image::from_packed(
          { ..image.frame, bits_per_sample: 9, },
          b"\xff\xff\x00\x00"[:],
          layout=PixelLayout::tight(storage=U16Big),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "image planes regions and signed error metrics use exact coordinates" {
  let image = {
    frame: { width: 2, height: 2, bits_per_sample: 8, components: 3, },
    samples: [1, 10, 20, 2, 11, 21, 3, 12, 22, 4, 13, 23],
  }
  assert_eq(image.row(1), [3, 12, 22, 4, 13, 23])
  assert_eq(image.sample(1, 1, component=2), 23)
  assert_eq(image.crop(1, 0, 1, 2).samples, [2, 11, 21, 4, 13, 23])
  assert_eq(image.plane(1).samples, [10, 11, 12, 13])
  assert_eq(
    merge_planes([image.plane(0), image.plane(1), image.plane(2)][:]),
    image,
  )
  let replacement = {
    frame: { ..image.frame, components: 1, },
    samples: [9, 8, 7, 6],
  }
  let changed = image.with_plane(0, replacement)
  assert_eq(changed.samples, [9, 10, 20, 8, 11, 21, 7, 12, 22, 6, 13, 23])
  let a = image_test_gray(8, [10, 10, 10, 10])
  let b = image_test_gray(8, [8, 11, 13, 10])
  let metrics = compare_images(a, b)
  assert_eq(metrics.maximum_error, 3)
  assert_eq(metrics.mean_error, 0.5)
  assert_eq(metrics.mean_absolute_error, 1.5)
  assert_eq(metrics.mean_squared_error, 3.5)
  assert_true(metrics.within_near(3))
  assert_true(
    try {
      ignore(verify_near(a, b, 2))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(image.crop(1, 0, 2, 1))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(image.sample(-1, 0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(merge_planes([image][:]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "tagged JSON preserves image precision and refuses ambiguous shapes" {
  let image = image_test_gray(16, [0, 255, 65535])
  assert_eq(Image::from_json(image.to_json()), image)
  let options = { ..EncodeOptions::default(), near: 3, interleave: Line, }
  assert_eq(EncodeOptions::from_json(options.to_json()), options)
  let layout = {
    order: Planar,
    storage: U16Little,
    row_stride: 8,
    plane_stride: 16,
  }
  assert_eq(PixelLayout::from_json(layout.to_json()), layout)
  for
    value in [
      Json::null(),
      {
        "format": "moonjls.image.v2",
        "frame": image.frame.to_json(),
        "samples": [0, 255, 65535],
      },
      {
        "format": "moonjls.image.v1",
        "frame": image.frame.to_json(),
        "samples": [0, 255],
      },
      {
        "format": "moonjls.image.v1",
        "frame": image.frame.to_json(),
        "samples": [0, 255, 65536],
      },
      {
        "format": "moonjls.image.v1",
        "frame": image.frame.to_json(),
        "samples": [0, 255, 1.5],
      },
      {
        "format": "moonjls.image.v1",
        "frame": image.frame.to_json(),
        "samples": [0, 255, 65535],
        "extra": true,
      },
    ] {
    assert_true(
      try {
        ignore(Image::from_json(value))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(
        Image::from_json(image.to_json(), limits={
          ..Limits::default(),
          samples: 2,
        }),
      )
      false
    } catch {
      _ => true
    },
  )
}
