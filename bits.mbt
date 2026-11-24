// JPEG-LS single-bit stuffing and limited Golomb coding, following ITU T.87 A.1/A.4.
// End-of-scan padding behavior adapted from CharLS 2.4.2 encoder_strategy.h.
// Copyright (c) Team CharLS. SPDX-License-Identifier: BSD-3-Clause.

///|
priv struct BitsReader {
  data : BytesView
  end : Int32
  mut position : Int32
  mut current : Int32
  mut remaining : Int32
  mut previous_ff : Bool
}

///|
fn BitsReader::new(
  data : BytesView,
  start : Int32,
  end : Int32,
) -> BitsReader raise JlsError {
  guard start >= 0 && start <= end && end <= data.length() else {
    raise Invalid(start, "invalid entropy range")
  }
  { data, end, position: start, current: 0, remaining: 0, previous_ff: false, }
}

///|
fn BitsReader::read_bit(self : BitsReader) -> Int32 raise JlsError {
  if self.remaining == 0 {
    guard self.position < self.end else {
      raise Truncated(self.position, "entropy code extends beyond scan")
    }
    let byte = self.data[self.position].to_int()
    guard !self.previous_ff || byte < 128 else {
      raise Invalid(self.position, "missing JPEG-LS stuffed zero bit")
    }
    self.current = byte
    self.remaining = if self.previous_ff { 7 } else { 8 }
    self.previous_ff = byte == 255
    self.position += 1
  }
  self.remaining -= 1
  (self.current >> self.remaining) & 1
}

///|
fn BitsReader::read_bits(
  self : BitsReader,
  count : Int32,
) -> Int32 raise JlsError {
  guard count >= 0 && count <= 30 else {
    raise Invalid(self.position, "invalid entropy bit count")
  }
  let mut value = 0
  for _ in 0..<count {
    value = (value << 1) | self.read_bit()
  }
  value
}

///|
fn BitsReader::read_unary(
  self : BitsReader,
  maximum : Int32,
) -> Int32 raise JlsError {
  guard maximum >= 0 && maximum <= 65535 else {
    raise Invalid(self.position, "invalid unary limit")
  }
  let mut zeros = 0
  while self.read_bit() == 0 {
    guard zeros < maximum else {
      raise Invalid(self.position - 1, "unary prefix exceeds code limit")
    }
    zeros += 1
  }
  zeros
}

///|
fn BitsReader::read_mapped(
  self : BitsReader,
  k : Int32,
  limit : Int32,
  qbpp : Int32,
) -> Int32 raise JlsError {
  guard k >= 0 &&
    k <= 16 &&
    qbpp >= 1 &&
    qbpp <= 16 &&
    limit > qbpp &&
    limit <= 64 else {
    raise Invalid(self.position, "invalid limited Golomb parameters")
  }
  let threshold = limit - qbpp - 1
  let quotient = self.read_unary(threshold)
  if quotient == threshold {
    self.read_bits(qbpp) + 1
  } else {
    (quotient << k) | self.read_bits(k)
  }
}

///|
fn BitsReader::finish(self : BitsReader) -> Unit raise JlsError {
  let mask = (1 << self.remaining) - 1
  guard (self.current & mask) == 0 else {
    raise Invalid(self.position - 1, "nonzero end-of-scan padding")
  }
  self.remaining = 0
  if self.previous_ff {
    guard self.position < self.end && self.data[self.position] == b'\x00' else {
      raise Truncated(
        self.position,
        "scan ending in FF requires zero-stuffed padding byte",
      )
    }
    self.position += 1
    self.previous_ff = false
  }
  guard self.position == self.end else {
    raise Invalid(
      self.position,
      "extra entropy bytes after reconstructed image",
    )
  }
}

///|
priv struct BitWriter {
  output : @buffer.Buffer
  maximum : Int32
  mut current : Int32
  mut used : Int32
  mut capacity : Int32
  mut closed : Bool
}

///|
fn BitWriter::new(maximum : Int32) -> BitWriter raise JlsError {
  guard maximum > 0 else {
    raise Invalid(0, "entropy output limit must be positive")
  }
  {
    output: @buffer.Buffer::Buffer(),
    maximum,
    current: 0,
    used: 0,
    capacity: 8,
    closed: false,
  }
}

///|
fn BitWriter::emit(self : BitWriter) -> Unit raise JlsError {
  guard self.output.length() < self.maximum else {
    raise Limit(self.output.length(), "compressed output exceeds budget")
  }
  self.output.write_byte(self.current.to_byte())
  self.capacity = if self.current == 255 { 7 } else { 8 }
  self.current = 0
  self.used = 0
}

///|
fn BitWriter::write_bit(self : BitWriter, value : Int32) -> Unit raise JlsError {
  guard !self.closed && (value == 0 || value == 1) else {
    raise Invalid(self.output.length(), "invalid bit or closed entropy writer")
  }
  self.current = (self.current << 1) | value
  self.used += 1
  if self.used == self.capacity {
    self.emit()
  }
}

///|
fn BitWriter::write_bits(
  self : BitWriter,
  value : Int32,
  count : Int32,
) -> Unit raise JlsError {
  guard count >= 0 && count <= 30 && value >= 0 && value < 1 << count else {
    raise Invalid(self.output.length(), "bit value does not fit declared width")
  }
  for i = count - 1; i >= 0; i = i - 1 {
    self.write_bit((value >> i) & 1)
  }
}

///|
fn BitWriter::write_unary(
  self : BitWriter,
  zeros : Int32,
) -> Unit raise JlsError {
  guard zeros >= 0 && zeros <= 65535 else {
    raise Invalid(self.output.length(), "invalid unary prefix")
  }
  for _ in 0..<zeros {
    self.write_bit(0)
  }
  self.write_bit(1)
}

///|
fn BitWriter::write_mapped(
  self : BitWriter,
  value : Int32,
  k : Int32,
  limit : Int32,
  qbpp : Int32,
) -> Unit raise JlsError {
  guard k >= 0 &&
    k <= 16 &&
    qbpp >= 1 &&
    qbpp <= 16 &&
    limit > qbpp &&
    limit <= 64 &&
    value >= 0 else {
    raise Invalid(
      self.output.length(),
      "invalid limited Golomb value or parameters",
    )
  }
  let quotient = value >> k
  let threshold = limit - qbpp - 1
  if quotient < threshold {
    self.write_unary(quotient)
    self.write_bits(value & ((1 << k) - 1), k)
  } else {
    guard value > 0 && value - 1 < 1 << qbpp else {
      raise Invalid(
        self.output.length(),
        "Golomb escape value exceeds precision",
      )
    }
    self.write_unary(threshold)
    self.write_bits(value - 1, qbpp)
  }
}

///|
fn BitWriter::finish(self : BitWriter) -> Bytes raise JlsError {
  guard !self.closed else {
    raise Invalid(self.output.length(), "entropy writer already finished")
  }
  if self.used > 0 {
    self.current = self.current << (self.capacity - self.used)
    self.emit()
  }
  if self.capacity == 7 {
    self.emit()
  }
  self.closed = true
  self.output.to_bytes()
}

///|
pub fn hex_encode(data : BytesView) -> String {
  let digits = b"0123456789abcdef"
  let out = @buffer.Buffer::Buffer()
  for byte in data {
    out.write_byte(digits[byte.to_int() >> 4])
    out.write_byte(digits[byte.to_int() & 15])
  }
  @utf8.decode_lossy(out.to_bytes()[:])
}

///|
pub fn hex_decode(text : String) -> Bytes raise JlsError {
  let bytes = @utf8.encode(text)
  guard bytes.length() % 2 == 0 else {
    raise Invalid(0, "odd hexadecimal input length")
  }
  let out = @buffer.Buffer::Buffer()
  for i = 0; i < bytes.length(); i = i + 2 {
    let high = hex_digit(bytes[i], i)
    let low = hex_digit(bytes[i + 1], i + 1)
    out.write_byte(((high << 4) | low).to_byte())
  }
  out.to_bytes()
}

///|
fn hex_digit(byte : Byte, position : Int32) -> Int32 raise JlsError {
  if byte >= b'0' && byte <= b'9' {
    byte.to_int() - 48
  } else if byte >= b'a' && byte <= b'f' {
    byte.to_int() - 87
  } else if byte >= b'A' && byte <= b'F' {
    byte.to_int() - 55
  } else {
    raise Invalid(position, "invalid hexadecimal digit")
  }
}
