// JPEG-LS marker structure follows ITU-T T.87 Annex C.
// SPDX-License-Identifier: BSD-3-Clause

///|
fn marker_range(
  data : BytesView,
  at : Int32,
  length : Int32,
) -> Unit raise JlsError {
  guard at >= 0 &&
    length >= 0 &&
    at <= data.length() &&
    length <= data.length() - at else {
    raise Truncated(at, "marker field extends beyond input")
  }
}

///|
fn marker_u16(data : BytesView, at : Int32) -> Int32 raise JlsError {
  marker_range(data, at, 2)
  (data[at].to_int() << 8) | data[at + 1].to_int()
}

///|
fn marker_write_u16(out : @buffer.Buffer, value : Int32) -> Unit {
  out.write_byte((value >> 8).to_byte())
  out.write_byte(value.to_byte())
}

///|
fn read_frame(
  payload : BytesView,
  at : Int32,
  limits : Limits,
) -> (Frame, Array[Int32]) raise JlsError {
  marker_range(payload, 0, 6)
  let components = payload[5].to_int()
  guard payload.length() == 6 + 3 * components else {
    raise Invalid(at, "SOF55 length disagrees with component count")
  }
  let frame = {
    width: marker_u16(payload, 3),
    height: marker_u16(payload, 1),
    bits_per_sample: payload[0].to_int(),
    components,
  }
  if frame.width > 0 && frame.height > 0 {
    ignore(frame.sample_count(limits~))
  } else {
    ignore(({ ..frame, width: 1, height: 1, } : Frame).sample_count(limits~))
  }
  let ids : Array[Int32] = []
  for i in 0..<components {
    let id = payload[6 + 3 * i].to_int()
    guard !ids.contains(id) else {
      raise Invalid(at + 6 + 3 * i, "duplicate frame component identifier")
    }
    guard payload[7 + 3 * i] == b'\x11' && payload[8 + 3 * i] == b'\x00' else {
      raise Unsupported(
        at + 7 + 3 * i,
        "subsampling and mapping tables are unsupported",
      )
    }
    ids.push(id)
  }
  (frame, ids)
}

///|
fn read_preset(payload : BytesView, at : Int32) -> Preset raise JlsError {
  marker_range(payload, 0, 1)
  guard payload[0] == b'\x01' else {
    raise Unsupported(
      at, "only LSE preset coding parameters type 1 is supported",
    )
  }
  guard payload.length() == 11 else {
    raise Invalid(at, "LSE preset segment must contain eleven bytes")
  }
  {
    maximum: marker_u16(payload, 1),
    threshold1: marker_u16(payload, 3),
    threshold2: marker_u16(payload, 5),
    threshold3: marker_u16(payload, 7),
    reset: marker_u16(payload, 9),
  }
}

///|
fn entropy_end(
  data : BytesView,
  start : Int32,
  restart_interval : Int32,
  maximum_markers : Int32,
) -> (Int32, Int32) raise JlsError {
  let mut at = start
  let mut restart_markers = 0
  while at < data.length() {
    if data[at] != b'\xff' {
      at += 1
      continue
    }
    marker_range(data, at, 2)
    if data[at + 1].to_int() < 128 {
      at += 2
      continue
    }
    let marker_start = at
    let mut code_at = at + 1
    while code_at < data.length() && data[code_at] == b'\xff' {
      code_at += 1
    }
    marker_range(data, code_at, 1)
    let code = data[code_at].to_int()
    if code >= 0xD0 && code <= 0xD7 {
      guard restart_interval > 0 else {
        raise Invalid(at, "restart marker without restart interval")
      }
      guard restart_markers < maximum_markers else {
        raise Limit(at, "restart markers exceed segment budget")
      }
      restart_markers += 1
      at = code_at + 1
      continue
    }
    return (marker_start, restart_markers)
  }
  raise Truncated(at, "scan has no following marker")
}

///|
fn read_scan(
  payload : BytesView,
  at : Int32,
  frame : Frame,
  frame_ids : Array[Int32],
  preset : Preset,
  entropy_offset : Int32,
  entropy_end : Int32,
  restart_interval : Int32,
) -> ScanInfo raise JlsError {
  marker_range(payload, 0, 1)
  let count = payload[0].to_int()
  guard count >= 1 &&
    count <= frame.components &&
    payload.length() == 4 + 2 * count else {
    raise Invalid(at, "invalid SOS component count or length")
  }
  let components : Array[Int32] = []
  for i in 0..<count {
    let id = payload[1 + 2 * i].to_int()
    let mut index = -1
    for j in 0..<frame_ids.length() {
      if frame_ids[j] == id {
        index = j
      }
    }
    guard index >= 0 && !components.contains(index) else {
      raise Invalid(at + 1 + 2 * i, "unknown or duplicate scan component")
    }
    guard payload[2 + 2 * i] == b'\x00' else {
      raise Unsupported(at + 2 + 2 * i, "scan mapping tables are unsupported")
    }
    components.push(index)
  }
  let near = payload[1 + 2 * count].to_int()
  let interleave = interleave_from_code(
    payload[2 + 2 * count].to_int(),
    at + 2 + 2 * count,
  )
  guard payload[3 + 2 * count] == b'\x00' else {
    raise Unsupported(at + 3 + 2 * count, "point transform is unsupported")
  }
  if interleave == None {
    guard count == 1 else {
      raise Invalid(at, "noninterleaved scan must contain one component")
    }
  } else {
    guard count >= 2 else {
      raise Invalid(at, "interleaved scan must contain at least two components")
    }
  }
  let preset = preset.resolve(frame.bits_per_sample, near)
  guard entropy_end > entropy_offset else {
    raise Invalid(entropy_offset, "scan has no entropy data")
  }
  {
    components,
    near,
    interleave,
    preset,
    entropy_offset,
    entropy_end,
    restart_interval,
  }
}

///|
/// Parses marker boundaries and metadata without reconstructing pixels. Successful
/// inspection establishes structure, not semantic validity of the entropy codes.
pub fn inspect(
  data : BytesView,
  limits~ : Limits = Limits::default(),
) -> Info raise JlsError {
  check_limits(limits)
  guard data.length() <= limits.compressed_bytes else {
    raise Limit(0, "input exceeds compressed byte budget")
  }
  marker_range(data, 0, 2)
  guard data[:2] == b"\xff\xd8"[:] else {
    raise Invalid(0, "expected JPEG SOI marker")
  }
  let mut at = 2
  let mut frame : Frame? = None
  let mut frame_ids : Array[Int32] = []
  let mut preset = Preset::automatic()
  let mut restart_interval = 0
  let mut segment_count = 0
  let mut metadata_size = 0
  let metadata : Array[Segment] = []
  let scans : Array[ScanInfo] = []
  let seen : Array[Int32] = []
  while at < data.length() {
    segment_count += 1
    guard segment_count <= limits.segments else {
      raise Limit(at, "marker count exceeds segment budget")
    }
    let offset = at
    guard data[at] == b'\xff' else {
      raise Invalid(at, "expected marker prefix")
    }
    while at < data.length() && data[at] == b'\xff' {
      at += 1
    }
    marker_range(data, at, 1)
    let marker = data[at].to_int()
    at += 1
    guard marker >= 128 else {
      raise Invalid(offset, "unexpected stuffed byte outside entropy data")
    }
    if marker == 0xD9 {
      let frame = match frame {
        Some(f) => f
        None => raise Invalid(offset, "EOI before frame header")
      }
      guard seen.length() == frame.components else {
        raise Invalid(offset, "not all frame components have a scan")
      }
      return { frame, scans, metadata, consumed: at, }
    }
    if marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) {
      raise Invalid(offset, "unexpected standalone marker")
    }
    let length = marker_u16(data, at)
    guard length >= 2 else {
      raise Invalid(at, "marker length is smaller than length field")
    }
    marker_range(data, at, length)
    let payload = data[at + 2:at + length]
    let payload_at = at + 2
    at += length
    if marker == 0xF7 {
      guard frame is None && scans.is_empty() else {
        raise Invalid(offset, "duplicate or misplaced SOF55")
      }
      let (value, ids) = read_frame(payload, payload_at, limits)
      frame = Some(value)
      frame_ids = ids
    } else if marker == 0xF8 {
      marker_range(payload, 0, 1)
      if payload[0] == b'\x04' {
        guard scans.is_empty() else {
          raise Invalid(offset, "extended dimensions after first scan")
        }
        let existing = match frame {
          Some(value) => value
          None => raise Invalid(offset, "extended dimensions precede SOF55")
        }
        frame = Some(extended_dimensions(payload, existing, payload_at, limits))
      } else {
        preset = read_preset(payload, payload_at)
      }
    } else if marker == 0xDD {
      guard payload.length() == 2 else {
        raise Invalid(offset, "restart interval must be sixteen bits")
      }
      restart_interval = marker_u16(payload, 0)
    } else if marker == 0xDA {
      let frame = match frame {
        Some(f) => f
        None => raise Invalid(offset, "scan precedes frame header")
      }
      if frame.width == 0 || frame.height == 0 {
        raise Unsupported(
          offset, "unresolved SOF55 dimensions; DNL is unsupported",
        )
      }
      ignore(frame.sample_count(limits~))
      let (end, restart_markers) = entropy_end(
        data,
        at,
        restart_interval,
        limits.segments - segment_count,
      )
      segment_count += restart_markers
      let scan = read_scan(
        payload, payload_at, frame, frame_ids, preset, at, end, restart_interval,
      )
      for component in scan.components {
        guard !seen.contains(component) else {
          raise Invalid(offset, "component appears in multiple scans")
        }
        seen.push(component)
      }
      scans.push(scan)
      at = end
    } else if (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE {
      guard payload.length() <= limits.metadata_bytes - metadata_size else {
        raise Limit(offset, "metadata exceeds byte budget")
      }
      metadata_size += payload.length()
      metadata.push({ marker, offset, data: payload.to_owned(), })
    } else {
      raise Unsupported(
        offset, "JPEG marker is outside the JPEG-LS baseline profile",
      )
    }
  }
  raise Truncated(at, "missing EOI marker")
}

///|
fn append_segment(
  out : @buffer.Buffer,
  marker : Int32,
  payload : BytesView,
  maximum : Int32,
) -> Unit raise JlsError {
  guard payload.length() <= 65533 else {
    raise Limit(out.length(), "JPEG segment payload exceeds sixteen-bit length")
  }
  guard out.length() <= maximum &&
    payload.length() + 4 <= maximum - out.length() else {
    raise Limit(out.length(), "codestream exceeds output budget")
  }
  out.write_byte(b'\xff')
  out.write_byte(marker.to_byte())
  marker_write_u16(out, payload.length() + 2)
  out.write_bytes(payload)
}

///|
fn write_frame(
  out : @buffer.Buffer,
  frame : Frame,
  limits : Limits,
) -> Unit raise JlsError {
  let payload = @buffer.Buffer::Buffer()
  payload.write_byte(frame.bits_per_sample.to_byte())
  let extended = frame.width > 65535 || frame.height > 65535
  marker_write_u16(payload, if extended { 0 } else { frame.height })
  marker_write_u16(payload, if extended { 0 } else { frame.width })
  payload.write_byte(frame.components.to_byte())
  for i in 0..<frame.components {
    payload.write_byte((i + 1).to_byte())
    payload.write_byte(b'\x11')
    payload.write_byte(b'\x00')
  }
  append_segment(out, 0xF7, payload.to_bytes()[:], limits.compressed_bytes)
  if extended {
    write_extended_dimensions(out, frame, limits)
  }
}

///|
fn write_preset(
  out : @buffer.Buffer,
  preset : Preset,
  limits : Limits,
) -> Unit raise JlsError {
  let payload = @buffer.Buffer::Buffer()
  payload.write_byte(b'\x01')
  for
    value in [
      preset.maximum,
      preset.threshold1,
      preset.threshold2,
      preset.threshold3,
      preset.reset,
    ] {
    marker_write_u16(payload, value)
  }
  append_segment(out, 0xF8, payload.to_bytes()[:], limits.compressed_bytes)
}

///|
fn write_scan_header(
  out : @buffer.Buffer,
  components : Array[Int32],
  options : EncodeOptions,
  limits : Limits,
) -> Unit raise JlsError {
  let payload = @buffer.Buffer::Buffer()
  payload.write_byte(components.length().to_byte())
  for component in components {
    payload.write_byte((component + 1).to_byte())
    payload.write_byte(b'\x00')
  }
  payload.write_byte(options.near.to_byte())
  payload.write_byte(options.interleave.code().to_byte())
  payload.write_byte(b'\x00')
  append_segment(out, 0xDA, payload.to_bytes()[:], limits.compressed_bytes)
}

///|
/// Encodes baseline JPEG-LS using reconstructed neighbors; NEAR is a per-sample
/// maximum absolute error bound, never an image quality percentage.
pub fn encode(
  image : Image,
  options~ : EncodeOptions = EncodeOptions::default(),
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  check_limits(limits)
  let preset = options.preset.resolve(image.frame.bits_per_sample, options.near)
  image.validate(maximum=preset.maximum, limits~)
  guard image.frame.components > 1 || options.interleave == None else {
    raise Invalid(0, "single-component frames require noninterleaved mode")
  }
  check_encoding_budget(image.frame, options, preset, limits)
  let out = @buffer.Buffer::Buffer()
  out.write_bytes(b"\xff\xd8"[:])
  write_frame(out, image.frame, limits)
  let default = Preset::defaults(
    (1 << image.frame.bits_per_sample) - 1,
    options.near,
  )
  if preset != default {
    write_preset(out, preset, limits)
  }
  let scans : Array[Array[Int32]] = if options.interleave == None {
    Array::makei(image.frame.components, i => [i])
  } else {
    [Array::makei(image.frame.components, i => i)]
  }
  for components in scans {
    write_scan_header(out, components, options, limits)
    let entropy = encode_scan(
      image,
      components,
      preset,
      options.near,
      options.interleave,
      limits,
    )
    guard entropy.length() <= limits.compressed_bytes - out.length() else {
      raise Limit(out.length(), "codestream entropy exceeds budget")
    }
    out.write_bytes(entropy[:])
  }
  guard out.length() <= limits.compressed_bytes - 2 else {
    raise Limit(out.length(), "codestream end exceeds budget")
  }
  out.write_bytes(b"\xff\xd9"[:])
  out.to_bytes()
}

///|
/// Strict single-image decode. Marker inspection alone never substitutes for
/// entropy decoding, reconstructed sample range checks and exact end padding.
pub fn decode(
  data : BytesView,
  limits~ : Limits = Limits::default(),
) -> Image raise JlsError {
  let info = inspect(data, limits~)
  guard info.consumed == data.length() else {
    raise Invalid(info.consumed, "trailing data after JPEG-LS image")
  }
  ignore(info.spiff_header(limits~))
  let transform = detected_transform(info)
  let samples = Array::make(info.frame.sample_count(limits~), 0)
  for scan in info.scans {
    if scan.restart_interval != 0 {
      decode_scan_restarted(
        data,
        info.frame,
        scan,
        (y, selected, row) => {
          for x in 0..<info.frame.width {
            for c in 0..<selected.length() {
              samples[(y * info.frame.width + x) * info.frame.components +
              selected[c]] = row[x * selected.length() + c]
            }
          }
        },
        limits,
      )
      continue
    }
    decode_scan(
      data,
      scan.entropy_offset,
      scan.entropy_end,
      info.frame,
      scan.components,
      scan.preset,
      scan.near,
      scan.interleave,
      samples,
      limits,
    )
  }
  let image = { frame: info.frame, samples, }
  if transform == Identity {
    image
  } else {
    image.color_transform(transform, inverse=true, limits~)
  }
}
