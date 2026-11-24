///|
/// Netpbm image plus the exact PNM MAXVAL. The Image precision is the smallest
/// JPEG-LS-supported precision that represents MAXVAL; values are never scaled.
pub(all) struct PnmImage {
  image : Image
  maximum : Int32
} derive(Eq, @debug.Debug)

///|
priv struct PnmCursor {
  data : BytesView
  mut position : Int32
  mut bound : Int32
}

///|
fn pnm_whitespace(byte : Byte) -> Bool {
  byte == b' ' ||
  byte == b'\t' ||
  byte == b'\r' ||
  byte == b'\n' ||
  byte == b'\x0b' ||
  byte == b'\x0c'
}

///|
fn PnmCursor::skip_space(self : PnmCursor) -> Unit raise JlsError {
  while self.position < self.data.length() {
    guard self.position < self.bound else {
      raise Limit(self.position, "PNM header exceeds metadata budget")
    }
    let byte = self.data[self.position]
    if pnm_whitespace(byte) {
      self.position += 1
    } else if byte == b'#' {
      self.position += 1
      while self.position < self.data.length() &&
            self.data[self.position] != b'\r' &&
            self.data[self.position] != b'\n' {
        guard self.position < self.bound else {
          raise Limit(
            self.position,
            "PNM header comment exceeds metadata budget",
          )
        }
        self.position += 1
      }
    } else {
      break
    }
  }
}

///|
fn PnmCursor::number(self : PnmCursor, maximum : Int32) -> Int32 raise JlsError {
  self.skip_space()
  let start = self.position
  guard start < self.data.length() else {
    raise Truncated(start, "missing PNM number")
  }
  let mut value = 0
  while self.position < self.data.length() {
    guard self.position < self.bound else {
      raise Limit(self.position, "PNM header exceeds metadata budget")
    }
    let byte = self.data[self.position]
    if pnm_whitespace(byte) || byte == b'#' {
      break
    }
    guard byte >= b'0' && byte <= b'9' else {
      raise Invalid(self.position, "PNM number is not unsigned decimal")
    }
    let digit = byte.to_int() - 48
    guard value <= (maximum - digit) / 10 && digit <= maximum else {
      raise Invalid(start, "PNM number exceeds its allowed range")
    }
    value = value * 10 + digit
    self.position += 1
  }
  guard self.position > start else { raise Invalid(start, "empty PNM number") }
  value
}

///|
fn pnm_precision(maximum : Int32) -> Int32 {
  let mut bits = 2
  while 1 << bits <= maximum {
    bits += 1
  }
  bits
}

///|
/// Parses one complete P2/P3/P5/P6 image. Concatenated images are intentionally
/// rejected. Binary samples start after exactly one separator (or CRLF), so a
/// first pixel containing whitespace or '#' is never treated as header text.
pub fn parse_pnm(
  data : BytesView,
  limits~ : Limits = Limits::default(),
) -> PnmImage raise JlsError {
  check_limits(limits)
  guard data.length() <= limits.compressed_bytes else {
    raise Limit(0, "PNM input exceeds byte budget")
  }
  guard data.length() >= 3 else {
    raise Truncated(0, "PNM magic is incomplete")
  }
  guard data[0] == b'P' else { raise Invalid(0, "expected Netpbm magic") }
  let kind = data[1]
  guard kind == b'2' || kind == b'3' || kind == b'5' || kind == b'6' else {
    raise Unsupported(1, "PNM profile supports P2/P3/P5/P6 only")
  }
  guard pnm_whitespace(data[2]) else {
    raise Invalid(2, "PNM magic needs a whitespace separator")
  }
  let cursor = {
    data,
    position: 2,
    bound: limits.metadata_bytes.min(data.length()),
  }
  let width = cursor.number(2147483645)
  let height = cursor.number(2147483647)
  let maximum = cursor.number(65535)
  guard width > 0 && height > 0 && maximum > 0 else {
    raise Invalid(cursor.position, "PNM dimensions and MAXVAL must be positive")
  }
  guard cursor.position < data.length() else {
    raise Truncated(cursor.position, "missing raster separator")
  }
  guard pnm_whitespace(data[cursor.position]) else {
    raise Invalid(cursor.position, "PNM raster needs one whitespace separator")
  }
  let separator = data[cursor.position]
  cursor.position += 1
  if separator == b'\r' &&
    cursor.position < data.length() &&
    data[cursor.position] == b'\n' {
    cursor.position += 1
  }
  guard cursor.position <= limits.metadata_bytes else {
    raise Limit(cursor.position, "PNM header exceeds metadata budget")
  }
  cursor.bound = data.length()
  let components = if kind == b'3' || kind == b'6' { 3 } else { 1 }
  let frame = {
    width,
    height,
    components,
    bits_per_sample: pnm_precision(maximum),
  }
  let count = frame.sample_count(limits~)
  let samples : Array[Int32] = []
  if kind == b'2' || kind == b'3' {
    for _ in 0..<count {
      samples.push(cursor.number(maximum))
    }
    cursor.skip_space()
    guard cursor.position == data.length() else {
      raise Invalid(cursor.position, "trailing PNM samples or images")
    }
  } else {
    let bytes_per_sample = if maximum < 256 { 1 } else { 2 }
    guard count <= limits.compressed_bytes / bytes_per_sample else {
      raise Limit(cursor.position, "PNM raster exceeds byte budget")
    }
    let expected = count * bytes_per_sample
    let remaining = data.length() - cursor.position
    guard remaining >= expected else {
      raise Truncated(cursor.position, "PNM raster is incomplete")
    }
    guard remaining == expected else {
      raise Invalid(
        cursor.position + expected,
        "bytes after complete PNM raster",
      )
    }
    for _ in 0..<count {
      let value = if bytes_per_sample == 1 {
        data[cursor.position].to_int()
      } else {
        (data[cursor.position].to_int() << 8) |
        data[cursor.position + 1].to_int()
      }
      guard value <= maximum else {
        raise Invalid(cursor.position, "PNM sample exceeds MAXVAL")
      }
      samples.push(value)
      cursor.position += bytes_per_sample
    }
  }
  { image: { frame, samples, }, maximum, }
}

///|
/// Emits a deterministic PGM or PPM without scaling or color-space conversion.
/// MAXVAL defaults to the image's full precision and may be preserved separately
/// from parse_pnm when a producer used a non-power-of-two range.
pub fn encode_pnm(
  image : Image,
  maximum? : Int32,
  ascii~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  let maxval = maximum.unwrap_or((1 << image.frame.bits_per_sample) - 1)
  image.validate(maximum=maxval, limits~)
  let frame = image.frame
  guard frame.components == 1 || frame.components == 3 else {
    raise Unsupported(0, "PNM output requires gray or RGB samples")
  }
  let kind = if ascii {
    if frame.components == 1 {
      "P2"
    } else {
      "P3"
    }
  } else if frame.components == 1 {
    "P5"
  } else {
    "P6"
  }
  let out = @buffer.Buffer::Buffer()
  let header = "\{kind}\n\{frame.width} \{frame.height}\n\{maxval}\n"
  out.write_string_utf8(header[:])
  guard out.length() <= limits.metadata_bytes &&
    out.length() <= limits.compressed_bytes else {
    raise Limit(0, "PNM output header exceeds byte budget")
  }
  if ascii {
    let row_samples = frame.width * frame.components
    for i in 0..<image.samples.length() {
      let token = image.samples[i].to_string() +
        (if (i + 1) % row_samples == 0 { "\n" } else { " " })
      let bytes = @utf8.encode(token)
      guard bytes.length() <= limits.compressed_bytes - out.length() else {
        raise Limit(i, "PNM output exceeds byte budget")
      }
      out.write_bytes(bytes[:])
    }
  } else {
    let bytes_per_sample = if maxval < 256 { 1 } else { 2 }
    guard image.samples.length() <=
      (limits.compressed_bytes - out.length()) / bytes_per_sample else {
      raise Limit(0, "PNM output raster exceeds byte budget")
    }
    for value in image.samples {
      if bytes_per_sample == 2 {
        out.write_byte((value >> 8).to_byte())
      }
      out.write_byte(value.to_byte())
    }
  }
  out.to_bytes()
}

///|
pub fn PnmImage::encode(
  self : PnmImage,
  ascii~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  encode_pnm(self.image, maximum=self.maximum, ascii~, limits~)
}
