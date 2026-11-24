///|
test "SPIFF wrapper after entropy is rejected before decoded rows escape" {
  let image = integration_image(7, 3, 8, 1)
  let bytes = with_spiff(encode(image)[:], SpiffHeader::default(image.frame))
  let info = inspect(bytes[:])
  let header = info.metadata[0]
  let eod = info.metadata[1]
  let wrapper_end = metadata_segment_end(bytes[:], eod.offset)
  for move_header in [false, true] {
    let out = @buffer.Buffer::Buffer()
    let start = if move_header { header.offset } else { eod.offset }
    out.write_bytes(bytes[:start])
    out.write_bytes(bytes[wrapper_end:bytes.length() - 2])
    out.write_bytes(bytes[start:wrapper_end])
    out.write_bytes(b"\xff\xd9"[:])
    let misplaced = out.to_bytes()
    expect_jls_error(() => ignore(decode(misplaced[:])))
    expect_jls_error(() => ignore(inspect(misplaced[:]).spiff_header()))
    let mut emitted = 0
    expect_jls_error(() => {
      ignore(decode_rows(misplaced[:], (_, _, _) => emitted += 1))
    })
    assert_eq(emitted, 0)
  }
}

///|
test "opaque annotations after a scan remain valid without a SPIFF wrapper" {
  let image = integration_image(5, 2, 8, 1)
  let raw = encode(image)
  let out = @buffer.Buffer::Buffer()
  out.write_bytes(raw[:raw.length() - 2])
  append_segment(
    out,
    0xFE,
    b"post-scan annotation"[:],
    Limits::default().compressed_bytes,
  )
  out.write_bytes(b"\xff\xd9"[:])
  let bytes = out.to_bytes()
  assert_eq(decode(bytes[:]), image)
  assert_eq(inspect(bytes[:]).spiff_header(), None)
}
