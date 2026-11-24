///|
test "row sinks reject recursive push and finish without corrupting the active stream" {
  for recursive_finish in [false, true] {
    let image = integration_image(
      23,
      if recursive_finish {
        1
      } else {
        3
      },
      12,
      3,
    )
    let options = { ..EncodeOptions::default(), interleave: Sample, }
    let out = @buffer.Buffer::Buffer()
    let mut handle : RowEncoder? = None
    let mut attempted = false
    let mut rejected = false
    let encoder = RowEncoder::new(
      image.frame,
      bytes => {
        out.write_bytes(bytes[:])
        if !attempted && handle is Some(active) {
          attempted = true
          rejected = try {
            if recursive_finish {
              active.finish()
            } else {
              active.push(image.row(1))
            }
            false
          } catch {
            _ => true
          }
        }
      },
      options~,
    )
    handle = Some(encoder)
    encoder.push(image.row(0))
    assert_true(attempted)
    assert_true(rejected)
    assert_eq(encoder.rows_written(), 1)
    for y in 1..<image.frame.height {
      encoder.push(image.row(y))
    }
    encoder.finish()
    assert_eq(out.to_bytes(), encode(image, options~))
    assert_eq(encoder.bytes_written(), out.length())
  }
}

///|
test "uncaught recursive sink errors poison the outer encoder" {
  let image = integration_image(23, 2, 8, 1)
  let mut handle : RowEncoder? = None
  let encoder = RowEncoder::new(image.frame, _ => {
    if handle is Some(active) {
      active.push(image.row(1))
    }
  })
  handle = Some(encoder)
  expect_jls_error(() => encoder.push(image.row(0)))
  expect_jls_error(() => encoder.finish())
}
