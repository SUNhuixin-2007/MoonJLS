///|
/// PAM supplies a raw file interchange for two- and four-component images,
/// including alpha. Tuple labels describe samples; the codec never color-converts.
pub(all) struct PamImage {
  image : Image
  maximum : Int32
  tuple_type : String
} derive(Eq, @debug.Debug)

///|
fn pam_trim(bytes : BytesView) -> BytesView {
  let mut start = 0
  let mut end = bytes.length()
  while start < end && pnm_whitespace(bytes[start]) {
    start += 1
  }
  while end > start && pnm_whitespace(bytes[end - 1]) {
    end -= 1
  }
  bytes[start:end]
}

///|
fn pam_decimal(
  bytes : BytesView,
  maximum : Int32,
  at : Int32,
) -> Int32 raise JlsError {
  guard !bytes.is_empty() else {
    raise Invalid(at, "missing PAM numeric value")
  }
  let mut value = 0
  for byte in bytes {
    guard byte >= b'0' && byte <= b'9' else {
      raise Invalid(at, "PAM number is not unsigned decimal")
    }
    let digit = byte.to_int() - 48
    guard digit <= maximum && value <= (maximum - digit) / 10 else {
      raise Invalid(at, "PAM number exceeds supported range")
    }
    value = value * 10 + digit
  }
  guard value > 0 else {
    raise Invalid(at, "PAM header number must be positive")
  }
  value
}

///|
fn pam_tuple_valid(
  tuple_type : String,
  components : Int32,
  maximum : Int32,
) -> Unit raise JlsError {
  let bytes = @utf8.encode(tuple_type)
  for byte in bytes {
    guard (byte >= b' ' && byte <= b'~') || byte == b'\t' else {
      raise Invalid(0, "PAM tuple type must be one ASCII header line")
    }
  }
  let valid = match tuple_type {
    "BLACKANDWHITE" => components == 1 && maximum == 1
    "BLACKANDWHITE_ALPHA" => components == 2 && maximum == 1
    "GRAYSCALE" => components == 1
    "GRAYSCALE_ALPHA" => components == 2
    "RGB" => components == 3
    "RGB_ALPHA" => components == 4
    _ => true
  }
  guard valid else {
    raise Invalid(0, "PAM defined tuple type disagrees with depth or MAXVAL")
  }
}

///|
pub fn PamImage::validate(
  self : PamImage,
  limits~ : Limits = Limits::default(),
) -> Unit raise JlsError {
  self.image.validate(maximum=self.maximum, limits~)
  pam_tuple_valid(self.tuple_type, self.image.frame.components, self.maximum)
}

///|
/// Parses one PAM P7 image. Numeric fields are unique; repeated TUPLTYPE lines
/// concatenate in order. Unknown keys fail explicitly, and raster bytes are never
/// tokenized as whitespace or comments after the ENDHDR line.
pub fn parse_pam(
  data : BytesView,
  limits~ : Limits = Limits::default(),
) -> PamImage raise JlsError {
  check_limits(limits)
  guard data.length() <= limits.compressed_bytes else {
    raise Limit(0, "PAM input exceeds byte budget")
  }
  let mut at = 0
  let mut width = 0
  let mut height = 0
  let mut depth = 0
  let mut maximum = 0
  let mut tuple_type = ""
  let mut first = true
  let mut ended = false
  while at < data.length() {
    let start = at
    while at < data.length() && data[at] != b'\n' {
      guard at < limits.metadata_bytes else {
        raise Limit(at, "PAM header exceeds metadata budget")
      }
      guard data[at] < b'\x80' && (data[at] >= b' ' || pnm_whitespace(data[at])) else {
        raise Invalid(at, "PAM header is not ASCII text")
      }
      at += 1
    }
    guard at < data.length() && at < limits.metadata_bytes else {
      raise Truncated(at, "PAM header line has no newline")
    }
    let line = pam_trim(data[start:at])
    at += 1
    if first {
      guard line == b"P7"[:] else {
        raise Invalid(start, "expected PAM P7 magic")
      }
      first = false
      continue
    }
    if line.is_empty() || line[0] == b'#' {
      continue
    }
    let mut split = 0
    while split < line.length() && !pnm_whitespace(line[split]) {
      split += 1
    }
    let key = @utf8.decode_lossy(line[:split])
    let rest = pam_trim(line[split:])
    match key {
      "WIDTH" => {
        guard width == 0 else { raise Invalid(start, "duplicate PAM WIDTH") }
        width = pam_decimal(rest, 2147483645, start)
      }
      "HEIGHT" => {
        guard height == 0 else { raise Invalid(start, "duplicate PAM HEIGHT") }
        height = pam_decimal(rest, 2147483647, start)
      }
      "DEPTH" => {
        guard depth == 0 else { raise Invalid(start, "duplicate PAM DEPTH") }
        depth = pam_decimal(rest, 4, start)
      }
      "MAXVAL" => {
        guard maximum == 0 else { raise Invalid(start, "duplicate PAM MAXVAL") }
        maximum = pam_decimal(rest, 65535, start)
      }
      "TUPLTYPE" => {
        guard !rest.is_empty() else {
          raise Invalid(start, "empty PAM tuple type line")
        }
        let value = @utf8.decode_lossy(rest)
        tuple_type = if tuple_type == "" {
          value
        } else {
          tuple_type + " " + value
        }
      }
      "ENDHDR" => {
        guard rest.is_empty() else {
          raise Invalid(start, "PAM ENDHDR has extra tokens")
        }
        ended = true
        break
      }
      _ => raise Unsupported(start, "unknown PAM header key: " + key)
    }
  }
  guard ended && width > 0 && height > 0 && depth > 0 && maximum > 0 else {
    raise Invalid(at, "PAM required header fields are incomplete")
  }
  let frame = {
    width,
    height,
    components: depth,
    bits_per_sample: pnm_precision(maximum),
  }
  let count = frame.sample_count(limits~)
  let bytes = if maximum < 256 { 1 } else { 2 }
  guard count <= (data.length() - at) / bytes &&
    count * bytes == data.length() - at else {
    raise Invalid(at, "PAM raster length disagrees with header")
  }
  pam_tuple_valid(tuple_type, depth, maximum)
  let samples = Array::make(count, 0)
  for i in 0..<count {
    let pos = at + i * bytes
    let value = if bytes == 1 {
      data[pos].to_int()
    } else {
      (data[pos].to_int() << 8) | data[pos + 1].to_int()
    }
    guard value <= maximum else {
      raise Invalid(pos, "PAM sample exceeds MAXVAL")
    }
    samples[i] = value
  }
  { image: { frame, samples, }, maximum, tuple_type, }
}

///|
/// Emits one PAM row at a time, including two/four-channel alpha rasters.
/// The host must discard partial output if any later callback fails.
pub fn write_pam_rows(
  frame : Frame,
  row_at : (Int32) -> Array[Int32] raise JlsError,
  emit : (Bytes) -> Unit raise JlsError,
  maximum? : Int32,
  tuple_type? : String,
  limits~ : Limits = Limits::default(),
) -> UInt64 raise JlsError {
  let count = frame.sample_count(limits~)
  let maximum = maximum.unwrap_or((1 << frame.bits_per_sample) - 1)
  guard maximum >= 1 && maximum <= (1 << frame.bits_per_sample) - 1 else {
    raise Invalid(0, "PAM MAXVAL exceeds sample precision")
  }
  let label = tuple_type.unwrap_or(
    match frame.components {
      1 => "GRAYSCALE"
      2 => "GRAYSCALE_ALPHA"
      3 => "RGB"
      _ => "RGB_ALPHA"
    },
  )
  pam_tuple_valid(label, frame.components, maximum)
  let tuple_line = if label == "" { "" } else { "TUPLTYPE \{label}\n" }
  let header = @utf8.encode(
    "P7\nWIDTH \{frame.width}\nHEIGHT \{frame.height}\nDEPTH \{frame.components}\nMAXVAL \{maximum}\n\{tuple_line}ENDHDR\n",
  )
  guard header.length() <= limits.metadata_bytes else {
    raise Limit(0, "PAM header exceeds metadata budget")
  }
  let sample_bytes = if maximum < 256 { 1 } else { 2 }
  guard header.length() <= limits.compressed_bytes &&
    count <= (limits.compressed_bytes - header.length()) / sample_bytes else {
    raise Limit(0, "PAM raster exceeds output budget")
  }
  emit(header)
  let mut written = header.length().to_uint64()
  let row_samples = frame.width * frame.components
  for y in 0..<frame.height {
    let values = row_at(y)
    guard values.length() == row_samples else {
      raise Invalid(y, "PAM row sample count disagrees with width")
    }
    for value in values {
      guard value >= 0 && value <= maximum else {
        raise Invalid(y, "PAM row sample exceeds MAXVAL")
      }
    }
    let row = @buffer.Buffer::Buffer()
    for value in values {
      if sample_bytes == 2 {
        row.write_byte((value >> 8).to_byte())
      }
      row.write_byte(value.to_byte())
    }
    let bytes = row.to_bytes()
    emit(bytes)
    written += bytes.length().to_uint64()
  }
  written
}

///|
pub fn encode_pam(
  image : Image,
  maximum? : Int32,
  tuple_type? : String,
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  image.validate(maximum?, limits~)
  let output = @buffer.Buffer::Buffer()
  ignore(
    write_pam_rows(
      image.frame,
      y => image.row(y, limits~),
      bytes => output.write_bytes(bytes[:]),
      maximum?,
      tuple_type?,
      limits~,
    ),
  )
  output.to_bytes()
}

///|
pub fn PamImage::encode(
  self : PamImage,
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  self.validate(limits~)
  encode_pam(
    self.image,
    maximum=self.maximum,
    tuple_type=self.tuple_type,
    limits~,
  )
}
