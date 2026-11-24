///|
priv struct RowEncodingState {
  frame : Frame
  options : EncodeOptions
  preset : Preset
  limits : Limits
  contexts : ScanContexts
  writer : BitWriter
  emit : (Bytes) -> Unit raise JlsError
  mut previous : Array[Array[Int32]]
  mut current : Array[Array[Int32]]
  runs : Array[Int32]
  mut rows : Int32
  mut bytes : Int32
  mut closed : Bool
  mut failed : Bool
}

///|
fn RowEncodingState::write(
  self : RowEncodingState,
  bytes : Bytes,
) -> Unit raise JlsError {
  guard bytes.length() <= self.limits.compressed_bytes - self.bytes else {
    raise Limit(self.bytes, "stream output exceeds compressed budget")
  }
  if !bytes.is_empty() {
    (self.emit)(bytes)
  }
  self.bytes += bytes.length()
}

///|
fn RowEncodingState::push(
  self : RowEncodingState,
  row : Array[Int32],
) -> Unit raise JlsError {
  guard !self.closed && !self.failed else {
    raise Invalid(self.rows, "row encoder is closed or failed")
  }
  errdefer {
    self.failed = true
  }
  guard self.rows < self.frame.height &&
    row.length() == self.frame.width * self.frame.components else {
    raise Invalid(self.rows, "unexpected row count or row width")
  }
  for value in row {
    guard value >= 0 && value <= self.preset.maximum else {
      raise Invalid(self.rows, "stream row value exceeds MAXVAL")
    }
  }
  let width = self.frame.width
  let count = self.frame.components
  for c in 0..<count {
    self.previous[c][width + 1] = self.previous[c][width]
    self.current[c][0] = self.previous[c][1]
    for x in 0..<width {
      self.current[c][x + 1] = row[x * count + c]
    }
  }
  if self.options.interleave == Sample {
    self.runs[0] = encode_joint_line(
      self.contexts,
      self.writer,
      self.previous,
      self.current,
      width,
      self.runs[0],
    )
  } else {
    for c in 0..<count {
      self.runs[c] = encode_scalar_line(
        self.contexts,
        self.writer,
        self.previous[c],
        self.current[c],
        width,
        self.runs[c],
      )
    }
  }
  let swap = self.previous
  self.previous = self.current
  self.current = swap
  self.rows += 1
  self.write(self.writer.take())
}

///|
fn RowEncodingState::finish(self : RowEncodingState) -> Unit raise JlsError {
  guard !self.closed && !self.failed else {
    raise Invalid(self.rows, "row encoder is closed or failed")
  }
  errdefer {
    self.failed = true
  }
  guard self.rows == self.frame.height else {
    raise Truncated(self.rows, "row encoder finished before all rows arrived")
  }
  self.write(self.writer.finish())
  self.write(b"\xff\xd9")
  self.closed = true
}

///|
/// Push-based encoder holding two reconstructed rows per component and partial
/// entropy bytes. The host controls row arrival and output backpressure.
pub struct RowEncoder {
  push_row : (Array[Int32]) -> Unit raise JlsError
  finish_stream : () -> Unit raise JlsError
  position : () -> Int32
  written : () -> Int32
}

///|
/// For canonical row order, grayscale uses NONE and multiple components use
/// LINE/SAMPLE. Planar multi-scan encoding requires encode_rows with row revisits.
/// The sink receives a header immediately; commit the sink only after finish.
pub fn RowEncoder::new(
  frame : Frame,
  emit : (Bytes) -> Unit raise JlsError,
  options~ : EncodeOptions = EncodeOptions::default(),
  limits~ : Limits = Limits::default(),
) -> RowEncoder raise JlsError {
  ignore(frame.sample_count(limits~))
  let preset = options.preset.resolve(frame.bits_per_sample, options.near)
  guard (frame.components == 1 && options.interleave == None) ||
    (frame.components > 1 && options.interleave != None) else {
    raise Unsupported(
      0, "push row encoder requires grayscale NONE or interleaved color",
    )
  }
  check_encoding_budget(frame, options, preset, limits)
  let header = @buffer.Buffer::Buffer()
  header.write_bytes(b"\xff\xd8"[:])
  write_frame(header, frame, limits)
  let defaults = Preset::defaults(
    (1 << frame.bits_per_sample) - 1,
    options.near,
  )
  if preset != defaults {
    write_preset(header, preset, limits)
  }
  write_scan_header(
    header,
    Array::makei(frame.components, c => c),
    options,
    limits,
  )
  let state : RowEncodingState = {
    frame,
    options,
    preset,
    limits,
    contexts: ScanContexts::new(preset, options.near),
    writer: BitWriter::new(limits.compressed_bytes),
    emit,
    previous: Array::makei(frame.components, _ => {
      Array::make(frame.width + 2, 0)
    }),
    current: Array::makei(frame.components, _ => Array::make(frame.width + 2, 0)),
    runs: Array::make(frame.components, 0),
    rows: 0,
    bytes: 0,
    closed: false,
    failed: false,
  }
  state.write(header.to_bytes())
  {
    push_row: row => state.push(row),
    finish_stream: () => state.finish(),
    position: () => state.rows,
    written: () => state.bytes,
  }
}

///|
pub fn RowEncoder::push(
  self : RowEncoder,
  row : Array[Int32],
) -> Unit raise JlsError {
  (self.push_row)(row)
}

///|
pub fn RowEncoder::finish(self : RowEncoder) -> Unit raise JlsError {
  (self.finish_stream)()
}

///|
pub fn RowEncoder::rows_written(self : RowEncoder) -> Int32 {
  (self.position)()
}

///|
pub fn RowEncoder::bytes_written(self : RowEncoder) -> Int32 {
  (self.written)()
}
