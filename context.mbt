// Adapted from CharLS 2.4.2 scan.h, context_regular_mode.h,
// context_run_mode.h and default_traits.h.
// Copyright (c) Team CharLS. SPDX-License-Identifier: BSD-3-Clause.

///|
priv struct CodingTraits {
  preset : Preset
  near : Int32
  range : Int32
  qbpp : Int32
  limit : Int32
}

///|
fn ceil_log2(value : Int32) -> Int32 {
  let mut result = 0
  while 1 << result < value {
    result += 1
  }
  result
}

///|
fn CodingTraits::new(preset : Preset, near : Int32) -> CodingTraits {
  let range = (preset.maximum + 2 * near) / (2 * near + 1) + 1
  let bpp = ceil_log2(preset.maximum + 1).max(2)
  {
    preset,
    near,
    range,
    qbpp: ceil_log2(range),
    limit: 2 * (bpp + bpp.max(8)),
  }
}

///|
fn CodingTraits::quantize(self : CodingTraits, error : Int32) -> Int32 {
  let quantized = if error > 0 {
    (error + self.near) / (2 * self.near + 1)
  } else {
    -((self.near - error) / (2 * self.near + 1))
  }
  let positive = if quantized < 0 { quantized + self.range } else { quantized }
  if positive >= (self.range + 1) / 2 {
    positive - self.range
  } else {
    positive
  }
}

///|
fn CodingTraits::reconstruct(
  self : CodingTraits,
  predicted : Int32,
  error : Int32,
) -> Int32 {
  let mut value = predicted + error * (2 * self.near + 1)
  if value < -self.near {
    value += self.range * (2 * self.near + 1)
  } else if value > self.preset.maximum + self.near {
    value -= self.range * (2 * self.near + 1)
  }
  value.max(0).min(self.preset.maximum)
}

///|
fn CodingTraits::gradient(self : CodingTraits, difference : Int32) -> Int32 {
  if difference <= -self.preset.threshold3 {
    -4
  } else if difference <= -self.preset.threshold2 {
    -3
  } else if difference <= -self.preset.threshold1 {
    -2
  } else if difference < -self.near {
    -1
  } else if difference <= self.near {
    0
  } else if difference < self.preset.threshold1 {
    1
  } else if difference < self.preset.threshold2 {
    2
  } else if difference < self.preset.threshold3 {
    3
  } else {
    4
  }
}

///|
fn CodingTraits::context(
  self : CodingTraits,
  ra : Int32,
  rb : Int32,
  rc : Int32,
  rd : Int32,
) -> Int32 {
  (self.gradient(rd - rb) * 9 + self.gradient(rb - rc)) * 9 +
  self.gradient(rc - ra)
}

///|
fn median_prediction(ra : Int32, rb : Int32, rc : Int32) -> Int32 {
  if rc >= ra.max(rb) {
    ra.min(rb)
  } else if rc <= ra.min(rb) {
    ra.max(rb)
  } else {
    ra + rb - rc
  }
}

///|
fn signed_direction(value : Int32) -> Int32 {
  if value < 0 {
    -1
  } else {
    1
  }
}

///|
fn map_error(error : Int32) -> Int32 {
  if error >= 0 {
    2 * error
  } else {
    -2 * error - 1
  }
}

///|
fn unmap_error(mapped : Int32) -> Int32 {
  if (mapped & 1) == 0 {
    mapped >> 1
  } else {
    -((mapped + 1) >> 1)
  }
}

///|
priv struct RegularContext {
  mut a : Int32
  mut b : Int32
  mut c : Int32
  mut n : Int32
}

///|
fn RegularContext::new(range : Int32) -> RegularContext {
  { a: ((range + 32) / 64).max(2), b: 0, c: 0, n: 1, }
}

///|
fn RegularContext::golomb(self : RegularContext) -> Int32 raise JlsError {
  let mut k = 0
  while self.n << k < self.a && k < 16 {
    k += 1
  }
  guard k < 16 else {
    raise Invalid(0, "regular context Golomb parameter exceeds range")
  }
  k
}

///|
fn RegularContext::correction(
  self : RegularContext,
  condition : Int32,
) -> Int32 {
  if condition != 0 {
    0
  } else if 2 * self.b + self.n - 1 < 0 {
    -1
  } else {
    0
  }
}

///|
fn RegularContext::update(
  self : RegularContext,
  error : Int32,
  near : Int32,
  reset : Int32,
) -> Unit raise JlsError {
  self.a += error.abs()
  self.b += error * (2 * near + 1)
  guard self.a < 16777216 && self.b.abs() < 16777216 else {
    raise Invalid(0, "adaptive regular context overflow")
  }
  if self.n == reset {
    self.a = self.a >> 1
    self.b = self.b >> 1
    self.n = self.n >> 1
  }
  self.n += 1
  if self.b + self.n <= 0 {
    self.b += self.n
    if self.b <= -self.n {
      self.b = -self.n + 1
    }
    if self.c > -128 {
      self.c -= 1
    }
  } else if self.b > 0 {
    self.b -= self.n
    if self.b > 0 {
      self.b = 0
    }
    if self.c < 127 {
      self.c += 1
    }
  }
}

///|
priv struct RunContext {
  kind : Int32
  mut a : Int32
  mut n : Int32
  mut nn : Int32
}

///|
fn RunContext::new(kind : Int32, range : Int32) -> RunContext {
  { kind, a: ((range + 32) / 64).max(2), n: 1, nn: 0, }
}

///|
fn RunContext::golomb(self : RunContext) -> Int32 raise JlsError {
  let temp = self.a + (self.n >> 1) * self.kind
  let mut n = self.n
  let mut k = 0
  while n < temp {
    n = n << 1
    k += 1
    guard k <= 16 else {
      raise Invalid(0, "run context Golomb parameter exceeds range")
    }
  }
  k
}

///|
fn RunContext::mapping(self : RunContext, error : Int32, k : Int32) -> Bool {
  (k == 0 && error > 0 && 2 * self.nn < self.n) ||
  (error < 0 && 2 * self.nn >= self.n) ||
  (error < 0 && k != 0)
}

///|
fn RunContext::unmap(self : RunContext, mapped : Int32, k : Int32) -> Int32 {
  let temp = mapped + self.kind
  let odd = (temp & 1) != 0
  let magnitude = (temp + (if odd { 1 } else { 0 })) / 2
  if (k != 0 || 2 * self.nn >= self.n) == odd {
    -magnitude
  } else {
    magnitude
  }
}

///|
fn RunContext::update(
  self : RunContext,
  error : Int32,
  mapped : Int32,
  reset : Int32,
) -> Unit raise JlsError {
  if error < 0 {
    self.nn += 1
  }
  self.a += (mapped + 1 - self.kind) >> 1
  guard self.a < 16777216 else {
    raise Invalid(0, "adaptive run context overflow")
  }
  if self.n == reset {
    self.a = self.a >> 1
    self.n = self.n >> 1
    self.nn = self.nn >> 1
  }
  self.n += 1
}

///|
fn run_exponent(index : Int32) -> Int32 {
  [
    0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 9,
    10, 11, 12, 13, 14, 15,
  ][index]
}
