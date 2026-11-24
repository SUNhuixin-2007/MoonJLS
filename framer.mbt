///|
enum FramingState {
  Start
  SoiCode
  MarkerPrefix
  MarkerCode
  LengthHigh
  LengthLow
  Payload
  Entropy
  EntropyFf
}

///|
/// Incremental framing of concatenated JPEG-LS codestreams. This stores one
/// compressed image, not decoded pixels, and does not pretend to decode a scan
/// before all its compressed bytes have arrived. Chunks may split any marker.
pub struct CodestreamFramer {
  limits : Limits
  batch_images : Int32
  buffer : @buffer.Buffer
  mut state : FramingState
  mut marker : Int32
  mut length : Int32
  mut remaining : Int32
  mut images : UInt64
  mut received : UInt64
  mut closed : Bool
  mut failed : Bool
}

///|
pub fn CodestreamFramer::new(
  limits~ : Limits = Limits::default(),
  batch_images~ : Int32 = 64,
) -> CodestreamFramer raise JlsError {
  check_limits(limits)
  guard batch_images >= 1 && batch_images <= 65535 else {
    raise Invalid(0, "invalid per-feed image count bound")
  }
  {
    limits,
    batch_images,
    buffer: @buffer.Buffer::Buffer(),
    state: Start,
    marker: 0,
    length: 0,
    remaining: 0,
    images: 0UL,
    received: 0UL,
    closed: false,
    failed: false,
  }
}

///|
fn CodestreamFramer::marker_code(
  self : CodestreamFramer,
  marker : Int32,
) -> Bool raise JlsError {
  guard marker >= 128 else {
    raise Invalid(self.buffer.length() - 1, "stuffed byte outside entropy scan")
  }
  if marker == 0xD9 {
    return true
  }
  guard marker != 0xD8 && !(marker >= 0xD0 && marker <= 0xD7) else {
    raise Invalid(self.buffer.length() - 1, "unexpected standalone JPEG marker")
  }
  self.marker = marker
  self.length = 0
  self.state = LengthHigh
  false
}

///|
fn CodestreamFramer::consume(
  self : CodestreamFramer,
  byte : Byte,
) -> Bool raise JlsError {
  let value = byte.to_int()
  match self.state {
    Start => {
      guard byte == b'\xff' else {
        raise Invalid(0, "stream image must start with SOI")
      }
      self.state = SoiCode
    }
    SoiCode => {
      guard byte == b'\xd8' else { raise Invalid(1, "invalid stream SOI code") }
      self.state = MarkerPrefix
    }
    MarkerPrefix => {
      guard byte == b'\xff' else {
        raise Invalid(self.buffer.length() - 1, "expected JPEG marker")
      }
      self.state = MarkerCode
    }
    MarkerCode => if byte != b'\xff' { return self.marker_code(value) }
    LengthHigh => {
      self.length = value << 8
      self.state = LengthLow
    }
    LengthLow => {
      self.length = self.length | value
      guard self.length >= 2 else {
        raise Invalid(self.buffer.length() - 2, "invalid JPEG segment length")
      }
      self.remaining = self.length - 2
      if self.remaining == 0 {
        self.state = if self.marker == 0xDA { Entropy } else { MarkerPrefix }
      } else {
        self.state = Payload
      }
    }
    Payload => {
      self.remaining -= 1
      if self.remaining == 0 {
        self.state = if self.marker == 0xDA { Entropy } else { MarkerPrefix }
      }
    }
    Entropy => if byte == b'\xff' { self.state = EntropyFf }
    EntropyFf =>
      if value < 128 || (value >= 0xD0 && value <= 0xD7) {
        self.state = Entropy
      } else if value != 255 {
        return self.marker_code(value)
      }
  }
  false
}

///|
/// Returns complete compressed images after structural inspection. A failed
/// feed poisons the object; reset is explicit and discards its incomplete tail.
pub fn CodestreamFramer::feed(
  self : CodestreamFramer,
  chunk : BytesView,
) -> Array[Bytes] raise JlsError {
  guard !self.failed && !self.closed else {
    raise Invalid(0, "framer is closed or failed")
  }
  errdefer {
    self.failed = true
  }
  guard chunk.length() <= self.limits.compressed_bytes else {
    raise Limit(0, "feed chunk exceeds compressed byte budget")
  }
  let complete : Array[Bytes] = []
  let mut batch_bytes = 0
  for byte in chunk {
    guard self.buffer.length() < self.limits.compressed_bytes else {
      raise Limit(self.buffer.length(), "incomplete image exceeds byte budget")
    }
    self.buffer.write_byte(byte)
    self.received += 1UL
    if self.consume(byte) {
      guard complete.length() < self.batch_images else {
        raise Limit(0, "too many images in one feed")
      }
      let image = self.buffer.to_bytes()
      guard image.length() <= self.limits.compressed_bytes - batch_bytes else {
        raise Limit(0, "completed image batch exceeds byte budget")
      }
      let info = inspect(image[:], limits=self.limits)
      guard info.consumed == image.length() else {
        raise Invalid(info.consumed, "ambiguous image framing boundary")
      }
      complete.push(image)
      batch_bytes += image.length()
      self.images += 1UL
      self.buffer.reset()
      self.state = Start
    }
  }
  complete
}

///|
pub fn CodestreamFramer::finish(self : CodestreamFramer) -> Unit raise JlsError {
  guard !self.failed && !self.closed else {
    raise Invalid(0, "framer is closed or failed")
  }
  self.closed = true
  if self.buffer.length() != 0 {
    self.failed = true
    raise Truncated(self.buffer.length(), "stream ends inside JPEG-LS image")
  }
}

///|
pub fn CodestreamFramer::reset(self : CodestreamFramer) -> Unit {
  self.buffer.reset()
  self.state = Start
  self.marker = 0
  self.length = 0
  self.remaining = 0
  self.images = 0UL
  self.received = 0UL
  self.closed = false
  self.failed = false
}

///|
pub fn CodestreamFramer::buffered_bytes(self : CodestreamFramer) -> Int32 {
  self.buffer.length()
}

///|
pub fn CodestreamFramer::image_count(self : CodestreamFramer) -> UInt64 {
  self.images
}

///|
pub fn CodestreamFramer::input_bytes(self : CodestreamFramer) -> UInt64 {
  self.received
}
