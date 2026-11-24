// Restart reset semantics follow CharLS 2.4.2 scan.h decode_lines/read_restart_marker.
// Copyright (c) Team CharLS. SPDX-License-Identifier: BSD-3-Clause.

///|
priv struct RestartRange {
  start : Int32
  end : Int32
  first_row : Int32
  rows : Int32
}

///|
fn restart_ranges(
  data : BytesView,
  frame : Frame,
  scan : ScanInfo,
) -> Array[RestartRange] raise JlsError {
  let interval = if scan.restart_interval == 0 {
    frame.height
  } else {
    scan.restart_interval
  }
  let expected = 1 + (frame.height - 1) / interval
  let ranges : Array[RestartRange] = []
  let mut start = scan.entropy_offset
  let mut at = start
  let mut row = 0
  while at < scan.entropy_end {
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
    while at < scan.entropy_end && data[at] == b'\xff' {
      at += 1
    }
    guard at < scan.entropy_end else {
      raise Truncated(at, "unfinished restart marker")
    }
    let code = data[at].to_int()
    let correct = 0xD0 + ranges.length() % 8
    guard code == correct && ranges.length() < expected - 1 else {
      raise Invalid(marker_start, "unexpected restart marker order or count")
    }
    guard marker_start > start else {
      raise Invalid(start, "empty restart entropy interval")
    }
    ranges.push({ start, end: marker_start, first_row: row, rows: interval, })
    row += interval
    at += 1
    start = at
  }
  guard ranges.length() == expected - 1 && scan.entropy_end > start else {
    raise Invalid(
      scan.entropy_end,
      "restart interval count disagrees with frame height",
    )
  }
  ranges.push({
    start,
    end: scan.entropy_end,
    first_row: row,
    rows: frame.height - row,
  })
  ranges
}

///|
fn decode_scan_restarted(
  data : BytesView,
  frame : Frame,
  scan : ScanInfo,
  emit : (Int32, Array[Int32], Array[Int32]) -> Unit raise JlsError,
  limits : Limits,
) -> Unit raise JlsError {
  for range in restart_ranges(data, frame, scan) {
    let section = { ..frame, height: range.rows, }
    decode_scan_rows(
      data,
      range.start,
      range.end,
      section,
      scan.components,
      scan.preset,
      scan.near,
      scan.interleave,
      (y, components, row) => emit(range.first_row + y, components, row),
      limits,
    )
  }
}

///|
/// Writes standard restart intervals measured in JPEG-LS scan lines. Every
/// interval resets predictive/context state and terminates its own stuffed bits.
/// This makes restart decoding testable with independent CharLS decoders even
/// though CharLS's encoder does not itself expose restart-marker generation.
pub fn encode_restarted(
  image : Image,
  interval : Int32,
  options~ : EncodeOptions = EncodeOptions::default(),
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  guard interval >= 1 && interval <= 65535 else {
    raise Invalid(0, "restart interval must be in 1..65535")
  }
  let frame = image.frame
  let preset = options.preset.resolve(frame.bits_per_sample, options.near)
  image.validate(maximum=preset.maximum, limits~)
  guard frame.components > 1 || options.interleave == None else {
    raise Invalid(0, "grayscale requires noninterleaved mode")
  }
  let out = @buffer.Buffer::Buffer()
  out.write_bytes(b"\xff\xd8"[:])
  write_frame(out, frame, limits)
  let defaults = Preset::defaults(
    (1 << frame.bits_per_sample) - 1,
    options.near,
  )
  if preset != defaults {
    write_preset(out, preset, limits)
  }
  let dri = @buffer.Buffer::Buffer()
  marker_write_u16(dri, interval)
  append_segment(out, 0xDD, dri.to_bytes()[:], limits.compressed_bytes)
  let groups : Array[Array[Int32]] = if options.interleave == None {
    Array::makei(frame.components, c => [c])
  } else {
    [Array::makei(frame.components, c => c)]
  }
  for components in groups {
    write_scan_header(out, components, options, limits)
    let mut start_row = 0
    let mut sequence = 0
    while start_row < frame.height {
      let first = start_row
      let rows = interval.min(frame.height - first)
      let section = { ..frame, height: rows, }
      let bytes = encode_scan_rows(
        section,
        components,
        preset,
        options.near,
        options.interleave,
        (y, selected) => {
          Array::makei(frame.width * selected.length(), i => {
            image.samples[((first + y) * frame.width + i / selected.length()) *
            frame.components +
            selected[i % selected.length()]]
          })
        },
        limits,
      )
      guard bytes.length() <= limits.compressed_bytes - out.length() else {
        raise Limit(0, "restart output exceeds byte budget")
      }
      out.write_bytes(bytes[:])
      start_row += rows
      if start_row < frame.height {
        guard 2 <= limits.compressed_bytes - out.length() else {
          raise Limit(0, "restart marker exceeds byte budget")
        }
        out.write_byte(b'\xff')
        out.write_byte((0xD0 + sequence).to_byte())
        sequence = (sequence + 1) % 8
      }
    }
  }
  guard 2 <= limits.compressed_bytes - out.length() else {
    raise Limit(0, "EOI exceeds byte budget")
  }
  out.write_bytes(b"\xff\xd9"[:])
  out.to_bytes()
}
