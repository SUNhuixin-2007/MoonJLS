///|
/// JPEG-LS LSE type 4 carries two-, three-, or four-byte dimensions when the
/// SOF55 sixteen-bit fields are zero. Internal indices stay checked signed Int.
fn extended_dimensions(
  payload : BytesView,
  frame : Frame,
  at : Int32,
  limits : Limits,
) -> Frame raise JlsError {
  marker_range(payload, 0, 2)
  let width = payload[1].to_int()
  guard payload[0] == b'\x04' &&
    width >= 2 &&
    width <= 4 &&
    payload.length() == 2 + 2 * width else {
    raise Invalid(at, "invalid LSE extended dimension layout")
  }
  let mut height = 0UL
  let mut columns = 0UL
  for i in 0..<width {
    height = (height << 8) | payload[2 + i].to_uint64()
    columns = (columns << 8) | payload[2 + width + i].to_uint64()
  }
  guard height > 0UL &&
    columns > 0UL &&
    height <= 2147483647UL &&
    columns <= 2147483647UL else {
    raise Unsupported(at, "extended dimensions exceed positive Int indexing")
  }
  let result = { ..frame, width: columns.to_int(), height: height.to_int(), }
  guard (frame.width == 0 || frame.width == result.width) &&
    (frame.height == 0 || frame.height == result.height) else {
    raise Invalid(at, "extended dimensions disagree with SOF55")
  }
  ignore(result.sample_count(limits~))
  result
}

///|
fn write_extended_dimensions(
  out : @buffer.Buffer,
  frame : Frame,
  limits : Limits,
) -> Unit raise JlsError {
  let payload = @buffer.Buffer::Buffer()
  payload.write_bytes(b"\x04\x04"[:])
  payload.write_uint_be(frame.height.reinterpret_as_uint())
  payload.write_uint_be(frame.width.reinterpret_as_uint())
  append_segment(out, 0xF8, payload.to_bytes()[:], limits.compressed_bytes)
}
