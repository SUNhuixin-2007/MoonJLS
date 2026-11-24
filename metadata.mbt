// SPIFF handling adapted from CharLS 2.4.2 jpeg_stream_writer.cpp and
// validate_spiff_header.cpp. Copyright (c) Team CharLS.
// SPDX-License-Identifier: BSD-3-Clause.

///|
pub(all) struct SpiffHeader {
  frame : Frame
  color_space : Int32
  resolution_units : Int32
  vertical_resolution : UInt32
  horizontal_resolution : UInt32
} derive(Eq, @debug.Debug)

///|
pub fn SpiffHeader::default(frame : Frame) -> SpiffHeader {
  {
    frame,
    color_space: if frame.components == 1 {
      8
    } else if frame.components == 3 {
      10
    } else {
      2
    },
    resolution_units: 0,
    vertical_resolution: 1U,
    horizontal_resolution: 1U,
  }
}

///|
pub fn SpiffHeader::validate(
  self : SpiffHeader,
  limits~ : Limits = Limits::default(),
) -> Unit raise JlsError {
  ignore(self.frame.sample_count(limits~))
  let components = self.frame.components
  let valid = match self.color_space {
    2 => true
    8 => components == 1
    1 | 3 | 4 | 9 | 10 | 11 | 14 => components == 3
    12 | 13 => components == 4
    _ => false
  }
  guard valid else {
    raise Invalid(0, "SPIFF color space disagrees with component count")
  }
  guard self.resolution_units >= 0 &&
    self.resolution_units <= 2 &&
    self.vertical_resolution > 0U &&
    self.horizontal_resolution > 0U else {
    raise Invalid(0, "invalid SPIFF image resolution")
  }
}

///|
fn metadata_u32(bytes : BytesView, at : Int32) -> UInt32 raise JlsError {
  marker_range(bytes, at, 4)
  (bytes[at].to_uint() << 24) |
  (bytes[at + 1].to_uint() << 16) |
  (bytes[at + 2].to_uint() << 8) |
  bytes[at + 3].to_uint()
}

///|
fn is_spiff(segment : Segment) -> Bool {
  segment.marker == 0xE8 &&
  segment.data.length() >= 6 &&
  segment.data[:6] == b"SPIFF\x00"[:]
}

///|
fn is_spiff_end(segment : Segment) -> Bool {
  segment.marker == 0xE8 && segment.data == b"\x00\x00\x00\x01\xff\xd8"
}

///|
fn is_hp(segment : Segment) -> Bool {
  segment.marker == 0xE8 &&
  segment.data.length() >= 4 &&
  segment.data[:4] == b"mrfx"[:]
}

///|
/// Finds and validates a SPIFF v2 header and end-of-directory wrapper. Directory
/// entry payloads are preserved as opaque APP8 data, not interpreted as images.
pub fn Info::spiff_header(
  self : Info,
  limits~ : Limits = Limits::default(),
) -> SpiffHeader? raise JlsError {
  check_limits(limits)
  let mut found : SpiffHeader? = None
  let mut header_at = -1
  let mut end_at = -1
  for segment in self.metadata {
    if is_spiff(segment) {
      guard found is None && segment.data.length() == 30 else {
        raise Invalid(segment.offset, "duplicate or malformed SPIFF header")
      }
      let bytes = segment.data
      guard bytes[6] == b'\x02' && bytes[7] == b'\x00' else {
        raise Unsupported(segment.offset, "only SPIFF version 2.0 is supported")
      }
      guard bytes[8] == b'\x00' && bytes[20] == b'\x06' else {
        raise Unsupported(
          segment.offset,
          "only unprofiled JPEG-LS SPIFF is supported",
        )
      }
      let height = metadata_u32(bytes[:], 10)
      let width = metadata_u32(bytes[:], 14)
      guard width <= 2147483647U && height <= 2147483647U else {
        raise Unsupported(segment.offset, "SPIFF frame exceeds signed indexing")
      }
      let frame = {
        width: width.reinterpret_as_int(),
        height: height.reinterpret_as_int(),
        components: bytes[9].to_int(),
        bits_per_sample: bytes[19].to_int(),
      }
      let header = {
        frame,
        color_space: bytes[18].to_int(),
        resolution_units: bytes[21].to_int(),
        vertical_resolution: metadata_u32(bytes[:], 22),
        horizontal_resolution: metadata_u32(bytes[:], 26),
      }
      header.validate(limits~)
      guard header.frame == self.frame else {
        raise Invalid(segment.offset, "SPIFF dimensions disagree with SOF55")
      }
      found = Some(header)
      header_at = segment.offset
    } else if is_spiff_end(segment) {
      guard end_at < 0 else {
        raise Invalid(segment.offset, "duplicate SPIFF end-of-directory")
      }
      end_at = segment.offset
    }
  }
  if found is Some(_) {
    guard end_at > header_at else {
      raise Invalid(header_at, "SPIFF end-of-directory missing or misplaced")
    }
  }
  found
}

///|
fn spiff_bytes(header : SpiffHeader) -> Bytes {
  let out = @buffer.Buffer::Buffer()
  out.write_bytes(b"SPIFF\x00\x02\x00\x00"[:])
  out.write_byte(header.frame.components.to_byte())
  out.write_uint_be(header.frame.height.reinterpret_as_uint())
  out.write_uint_be(header.frame.width.reinterpret_as_uint())
  out.write_byte(header.color_space.to_byte())
  out.write_byte(header.frame.bits_per_sample.to_byte())
  out.write_byte(b'\x06')
  out.write_byte(header.resolution_units.to_byte())
  out.write_uint_be(header.vertical_resolution)
  out.write_uint_be(header.horizontal_resolution)
  out.to_bytes()
}

///|
fn metadata_segment_end(
  data : BytesView,
  start : Int32,
) -> Int32 raise JlsError {
  let mut at = start
  marker_range(data, at, 1)
  while at < data.length() && data[at] == b'\xff' {
    at += 1
  }
  marker_range(data, at, 3)
  let length = marker_u16(data, at + 1)
  marker_range(data, at + 1, length)
  at + 1 + length
}

///|
fn copy_metadata_selection(
  data : BytesView,
  info : Info,
  keep : (Segment) -> Bool,
  limits : Limits,
) -> Bytes raise JlsError {
  let out = @buffer.Buffer::Buffer()
  let mut at = 0
  for segment in info.metadata {
    if !keep(segment) {
      out.write_bytes(data[at:segment.offset])
      at = metadata_segment_end(data, segment.offset)
    }
  }
  out.write_bytes(data[at:info.consumed])
  guard out.length() <= limits.compressed_bytes else {
    raise Limit(0, "metadata output exceeds budget")
  }
  out.to_bytes()
}

///|
/// Removes annotations without decoding pixels. Essential HP transform markers
/// remain, because dropping them would change the reconstructed color values.
pub fn strip_metadata(
  data : BytesView,
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  let info = inspect(data, limits~)
  guard info.consumed == data.length() else {
    raise Invalid(info.consumed, "trailing codestream data")
  }
  ignore(detected_transform(info))
  copy_metadata_selection(data, info, is_hp, limits)
}

///|
/// Replaces application annotations and comments. SPIFF/HP markers must be
/// created through their typed APIs, so arbitrary payloads cannot mislabel pixels.
pub fn with_metadata(
  data : BytesView,
  metadata : Array[Segment],
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  check_limits(limits)
  guard metadata.length() <= limits.segments else {
    raise Limit(0, "metadata segment budget exceeded")
  }
  let bare = strip_metadata(data, limits~)
  let out = @buffer.Buffer::Buffer()
  out.write_bytes(bare[:2])
  let mut total = 0
  for segment in metadata {
    guard (
        (segment.marker >= 0xE0 && segment.marker <= 0xEF) ||
        segment.marker == 0xFE
      ) &&
      !is_hp(segment) &&
      !is_spiff(segment) &&
      !is_spiff_end(segment) else {
      raise Invalid(0, "only nonessential APP/COM annotations are accepted")
    }
    guard segment.data.length() <= limits.metadata_bytes - total else {
      raise Limit(0, "metadata byte budget exceeded")
    }
    total += segment.data.length()
    append_segment(
      out,
      segment.marker,
      segment.data[:],
      limits.compressed_bytes,
    )
  }
  guard bare.length() - 2 <= limits.compressed_bytes - out.length() else {
    raise Limit(0, "metadata output exceeds compressed budget")
  }
  out.write_bytes(bare[2:])
  let result = out.to_bytes()
  ignore(inspect(result[:], limits~))
  result
}

///|
pub fn with_spiff(
  data : BytesView,
  header : SpiffHeader,
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  let info = inspect(data, limits~)
  header.validate(limits~)
  guard header.frame == info.frame && info.consumed == data.length() else {
    raise Invalid(0, "SPIFF frame or input boundary mismatch")
  }
  ignore(info.spiff_header(limits~))
  let bare = copy_metadata_selection(
    data,
    info,
    s => !is_spiff(s) && !is_spiff_end(s),
    limits,
  )
  let out = @buffer.Buffer::Buffer()
  out.write_bytes(bare[:2])
  append_segment(out, 0xE8, spiff_bytes(header)[:], limits.compressed_bytes)
  append_segment(
    out,
    0xE8,
    b"\x00\x00\x00\x01\xff\xd8"[:],
    limits.compressed_bytes,
  )
  guard bare.length() - 2 <= limits.compressed_bytes - out.length() else {
    raise Limit(0, "SPIFF output exceeds compressed budget")
  }
  out.write_bytes(bare[2:])
  let result = out.to_bytes()
  ignore(inspect(result[:], limits~).spiff_header(limits~))
  result
}
