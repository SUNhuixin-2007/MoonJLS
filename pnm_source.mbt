///|
/// Immutable host byte source. Reads must return exactly length bytes, with
/// offsets expressed as UInt64 so callers need not narrow large file positions.
pub struct ByteSource {
  size : UInt64
  read_at : (UInt64, Int32) -> Bytes raise JlsError
}

///|
pub fn ByteSource::new(
  size : UInt64,
  read_at : (UInt64, Int32) -> Bytes raise JlsError,
) -> ByteSource {
  { size, read_at, }
}

///|
pub fn ByteSource::size(self : ByteSource) -> UInt64 {
  self.size
}

///|
pub fn ByteSource::from_bytes(bytes : Bytes) -> ByteSource {
  ByteSource::new(bytes.length().to_uint64(), (offset, length) => {
    guard length >= 0 &&
      offset <= bytes.length().to_uint64() &&
      length.to_uint64() <= bytes.length().to_uint64() - offset else {
      raise Truncated(0, "byte source range outside input")
    }
    let start = offset.to_int()
    bytes[start:start + length].to_owned()
  })
}

///|
pub fn ByteSource::read(
  self : ByteSource,
  offset : UInt64,
  length : Int32,
) -> Bytes raise JlsError {
  guard length >= 0 &&
    offset <= self.size &&
    length.to_uint64() <= self.size - offset else {
    raise Truncated(0, "byte source read exceeds file at \{offset}")
  }
  let data = (self.read_at)(offset, length)
  guard data.length() == length else {
    raise Truncated(0, "short byte source read at \{offset}")
  }
  data
}

///|
pub fn ByteSource::slice(
  self : ByteSource,
  offset : UInt64,
  length : UInt64,
) -> ByteSource raise JlsError {
  guard offset <= self.size && length <= self.size - offset else {
    raise Invalid(0, "source slice outside file")
  }
  ByteSource::new(length, (at, count) => self.read(offset + at, count))
}

///|
priv struct SourceHeaderCursor {
  source : ByteSource
  start : UInt64
  maximum : Int32
  mut position : Int32
  mut cache_start : Int32
  mut cache : Bytes
}

///|
fn SourceHeaderCursor::peek(self : SourceHeaderCursor) -> Byte? raise JlsError {
  guard self.position <= self.maximum else {
    raise Limit(self.position, "PNM header exceeds metadata budget")
  }
  guard self.start <= self.source.size &&
    self.position.to_uint64() <= self.source.size - self.start else {
    raise Truncated(self.position, "PNM header exceeds source")
  }
  let absolute = self.start + self.position.to_uint64()
  if absolute == self.source.size {
    return None
  }
  guard absolute < self.source.size else {
    raise Truncated(self.position, "PNM header exceeds source")
  }
  if self.position < self.cache_start ||
    self.position - self.cache_start >= self.cache.length() {
    let remaining = self.source.size - absolute
    let count = if remaining < 256UL { remaining.to_int() } else { 256 }
    self.cache = self.source.read(absolute, count)
    self.cache_start = self.position
  }
  Some(self.cache[self.position - self.cache_start])
}

///|
fn SourceHeaderCursor::take(self : SourceHeaderCursor) -> Byte raise JlsError {
  let value = match self.peek() {
    Some(byte) => byte
    None => raise Truncated(self.position, "PNM header is incomplete")
  }
  guard self.position < self.maximum else {
    raise Limit(self.position, "PNM header exceeds metadata budget")
  }
  self.position += 1
  value
}

///|
fn SourceHeaderCursor::space(self : SourceHeaderCursor) -> Unit raise JlsError {
  while self.peek() is Some(byte) {
    if pnm_whitespace(byte) {
      ignore(self.take())
    } else if byte == b'#' {
      ignore(self.take())
      while self.peek() is Some(part) {
        if part == b'\r' || part == b'\n' {
          break
        }
        ignore(self.take())
      }
    } else {
      break
    }
  }
}

///|
fn SourceHeaderCursor::decimal(
  self : SourceHeaderCursor,
  maximum : Int32,
) -> Int32 raise JlsError {
  self.space()
  let start = self.position
  let mut value = 0
  while self.peek() is Some(byte) {
    if pnm_whitespace(byte) || byte == b'#' {
      break
    }
    guard byte >= b'0' && byte <= b'9' else {
      raise Invalid(self.position, "PNM header number is not decimal")
    }
    let digit = byte.to_int() - 48
    guard digit <= maximum && value <= (maximum - digit) / 10 else {
      raise Invalid(start, "PNM number exceeds range")
    }
    value = value * 10 + digit
    ignore(self.take())
  }
  guard self.position > start else {
    raise Invalid(start, "missing PNM header number")
  }
  value
}

///|
/// Binary P5/P6 raster descriptor. Only the bounded header and requested rows
/// are read. The caller keeps the source stable; no filesystem handles are owned.
pub struct PnmSource {
  source : ByteSource
  frame : Frame
  maximum : Int32
  raster_offset : UInt64
  row_bytes : Int32
  sample_bytes : Int32
  limits : Limits
}

///|
pub fn PnmSource::open(
  source : ByteSource,
  start~ : UInt64 = 0UL,
  limits~ : Limits = Limits::default(),
) -> PnmSource raise JlsError {
  check_limits(limits)
  guard start <= source.size && limits.metadata_bytes >= 3 else {
    raise Invalid(0, "invalid PNM source start or header budget")
  }
  let cursor = {
    source,
    start,
    maximum: limits.metadata_bytes,
    position: 0,
    cache_start: 0,
    cache: b"",
  }
  guard cursor.take() == b'P' else {
    raise Invalid(0, "expected PNM source magic")
  }
  let kind = cursor.take()
  guard kind == b'5' || kind == b'6' else {
    raise Unsupported(1, "row source supports binary P5/P6 only")
  }
  guard pnm_whitespace(cursor.take()) else {
    raise Invalid(2, "PNM magic requires whitespace")
  }
  let width = cursor.decimal(65535)
  let height = cursor.decimal(65535)
  let maximum = cursor.decimal(65535)
  guard maximum >= 1 else {
    raise Invalid(cursor.position, "PNM MAXVAL must be positive")
  }
  let separator = cursor.take()
  guard pnm_whitespace(separator) else {
    raise Invalid(
      cursor.position - 1,
      "PNM raster requires a whitespace separator",
    )
  }
  if separator == b'\r' && cursor.peek() == Some(b'\n') {
    ignore(cursor.take())
  }
  let frame = {
    width,
    height,
    bits_per_sample: pnm_precision(maximum),
    components: if kind == b'6' {
      3
    } else {
      1
    },
  }
  let count = frame.sample_count(limits~)
  let sample_bytes = if maximum < 256 { 1 } else { 2 }
  let raster_offset = start + cursor.position.to_uint64()
  let payload_length = count.to_uint64() * sample_bytes.to_uint64()
  guard raster_offset <= source.size &&
    payload_length == source.size - raster_offset else {
    raise Invalid(
      cursor.position,
      "PNM source length disagrees with raster dimensions",
    )
  }
  {
    source,
    frame,
    maximum,
    raster_offset,
    row_bytes: width * frame.components * sample_bytes,
    sample_bytes,
    limits,
  }
}

///|
pub fn PnmSource::frame(self : PnmSource) -> Frame {
  self.frame
}

///|
pub fn PnmSource::maximum(self : PnmSource) -> Int32 {
  self.maximum
}

///|
pub fn PnmSource::raster_offset(self : PnmSource) -> UInt64 {
  self.raster_offset
}

///|
/// Selected components preserve caller order, with each pixel's values adjacent.
/// An omitted selection reads all channels; repeated component indices fail.
pub fn PnmSource::row(
  self : PnmSource,
  y : Int32,
  components? : Array[Int32],
) -> Array[Int32] raise JlsError {
  guard y >= 0 && y < self.frame.height else {
    raise Invalid(y, "row outside PNM raster")
  }
  let selected = components.unwrap_or(
    Array::makei(self.frame.components, c => c),
  )
  validate_scan_components(
    self.frame,
    selected,
    if selected.length() == 1 {
      None
    } else {
      Line
    },
  )
  let bytes = self.source.read(
    self.raster_offset + y.to_uint64() * self.row_bytes.to_uint64(),
    self.row_bytes,
  )
  let values = Array::make(self.frame.width * selected.length(), 0)
  for x in 0..<self.frame.width {
    for c in 0..<selected.length() {
      let at = (x * self.frame.components + selected[c]) * self.sample_bytes
      let value = if self.sample_bytes == 1 {
        bytes[at].to_int()
      } else {
        (bytes[at].to_int() << 8) | bytes[at + 1].to_int()
      }
      guard value <= self.maximum else {
        raise Invalid(at, "PNM source sample exceeds MAXVAL")
      }
      values[x * selected.length() + c] = value
    }
  }
  values
}

///|
pub fn PnmSource::encode(
  self : PnmSource,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> Bytes raise JlsError {
  let preset = if options.preset.maximum == 0 {
    { ..options.preset, maximum: self.maximum, }
  } else {
    options.preset
  }
  guard preset.maximum == self.maximum else {
    raise Invalid(0, "encoding MAXVAL disagrees with PNM source")
  }
  encode_rows(
    self.frame,
    (y, components) => self.row(y, components~),
    options={ ..options, preset, },
    limits=self.limits,
  )
}

///|
/// Emits binary P5/P6 incrementally. Every row is checked before it is written;
/// earlier callback effects remain if a later row fails, so hosts commit on success.
pub fn write_pnm_rows(
  frame : Frame,
  row_at : (Int32) -> Array[Int32] raise JlsError,
  emit : (Bytes) -> Unit raise JlsError,
  maximum? : Int32,
  limits~ : Limits = Limits::default(),
) -> UInt64 raise JlsError {
  let count = frame.sample_count(limits~)
  guard frame.components == 1 || frame.components == 3 else {
    raise Unsupported(0, "PNM supports one or three components")
  }
  let maximum = maximum.unwrap_or((1 << frame.bits_per_sample) - 1)
  guard maximum >= 1 && maximum < 1 << frame.bits_per_sample else {
    raise Invalid(0, "invalid PNM row MAXVAL")
  }
  let magic = if frame.components == 1 { "P5" } else { "P6" }
  let header = @utf8.encode(
    "\{magic}\n\{frame.width} \{frame.height}\n\{maximum}\n",
  )
  let sample_bytes = if maximum < 256 { 1 } else { 2 }
  let total = header.length().to_uint64() +
    count.to_uint64() * sample_bytes.to_uint64()
  guard total <= limits.compressed_bytes.to_uint64() else {
    raise Limit(0, "PNM row output exceeds byte budget")
  }
  emit(header)
  for y in 0..<frame.height {
    let row = row_at(y)
    guard row.length() == frame.width * frame.components else {
      raise Invalid(y, "PNM output row has wrong sample count")
    }
    let bytes = @buffer.Buffer::Buffer()
    for value in row {
      guard value >= 0 && value <= maximum else {
        raise Invalid(y, "PNM output row exceeds MAXVAL")
      }
      if sample_bytes == 2 {
        bytes.write_byte((value >> 8).to_byte())
      }
      bytes.write_byte(value.to_byte())
    }
    emit(bytes.to_bytes())
  }
  total
}
