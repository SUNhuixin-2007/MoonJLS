// Adapted from CharLS 2.4.2 jpegls_preset_coding_parameters.h / default_traits.h.
// Copyright (c) Team CharLS. SPDX-License-Identifier: BSD-3-Clause.

///|
fn check_limits(limits : Limits) -> Unit raise JlsError {
  guard limits.pixels > 0 &&
    limits.samples > 0 &&
    limits.compressed_bytes > 0 &&
    limits.metadata_bytes >= 0 &&
    limits.segments > 0 else {
    raise Invalid(0, "invalid resource limits")
  }
}

///|
pub fn Frame::sample_count(
  self : Frame,
  limits~ : Limits = Limits::default(),
) -> Int32 raise JlsError {
  check_limits(limits)
  guard self.width > 0 &&
    self.width <= 65535 &&
    self.height > 0 &&
    self.height <= 65535 else {
    raise Invalid(0, "frame dimensions must be in 1..65535")
  }
  guard self.bits_per_sample >= 2 && self.bits_per_sample <= 16 else {
    raise Unsupported(0, "sample precision must be in 2..16")
  }
  guard self.components >= 1 && self.components <= 4 else {
    raise Unsupported(0, "this profile supports one to four components")
  }
  guard self.width <= limits.pixels / self.height else {
    raise Limit(0, "frame exceeds pixel limit")
  }
  let pixels = self.width * self.height
  guard pixels <= limits.samples / self.components else {
    raise Limit(0, "frame exceeds sample limit")
  }
  pixels * self.components
}

///|
pub fn Image::validate(
  self : Image,
  maximum? : Int32,
  limits~ : Limits = Limits::default(),
) -> Unit raise JlsError {
  let count = self.frame.sample_count(limits~)
  guard self.samples.length() == count else {
    raise Invalid(0, "sample count disagrees with frame")
  }
  let maxval = maximum.unwrap_or((1 << self.frame.bits_per_sample) - 1)
  guard maxval >= 1 && maxval < 1 << self.frame.bits_per_sample else {
    raise Invalid(0, "maximum sample value exceeds precision")
  }
  for i in 0..<count {
    guard self.samples[i] >= 0 && self.samples[i] <= maxval else {
      raise Invalid(i, "sample exceeds allowed range")
    }
  }
}

///|
fn preset_clamp(value : Int32, minimum : Int32, maximum : Int32) -> Int32 {
  if value > maximum || value < minimum {
    minimum
  } else {
    value
  }
}

///|
pub fn Preset::defaults(maximum : Int32, near : Int32) -> Preset raise JlsError {
  guard maximum >= 1 &&
    maximum <= 65535 &&
    near >= 0 &&
    near <= maximum / 2 &&
    near <= 255 else {
    raise Invalid(0, "invalid MAXVAL or NEAR")
  }
  let (t1, t2, t3) = if maximum >= 128 {
    let factor = (maximum.min(4095) + 128) / 256
    let a = preset_clamp(factor + 2 + 3 * near, near + 1, maximum)
    let b = preset_clamp(factor * 4 + 3 + 5 * near, a, maximum)
    (a, b, preset_clamp(factor * 17 + 4 + 7 * near, b, maximum))
  } else {
    let factor = 256 / (maximum + 1)
    let a = preset_clamp((3 / factor + 3 * near).max(2), near + 1, maximum)
    let b = preset_clamp((7 / factor + 5 * near).max(3), a, maximum)
    (a, b, preset_clamp((21 / factor + 7 * near).max(4), b, maximum))
  }
  { maximum, threshold1: t1, threshold2: t2, threshold3: t3, reset: 64, }
}

///|
pub fn Preset::resolve(
  self : Preset,
  bits_per_sample : Int32,
  near : Int32,
) -> Preset raise JlsError {
  guard bits_per_sample >= 2 && bits_per_sample <= 16 else {
    raise Invalid(0, "invalid precision")
  }
  let bound = (1 << bits_per_sample) - 1
  let maximum = if self.maximum == 0 { bound } else { self.maximum }
  guard maximum >= 1 && maximum <= bound else {
    raise Invalid(0, "preset MAXVAL exceeds precision")
  }
  let defaults = Preset::defaults(maximum, near)
  let threshold1 = if self.threshold1 == 0 {
    defaults.threshold1
  } else {
    self.threshold1
  }
  let threshold2 = if self.threshold2 == 0 {
    defaults.threshold2
  } else {
    self.threshold2
  }
  let threshold3 = if self.threshold3 == 0 {
    defaults.threshold3
  } else {
    self.threshold3
  }
  let reset = if self.reset == 0 { defaults.reset } else { self.reset }
  guard threshold1 >= near + 1 &&
    threshold1 <= maximum &&
    threshold2 >= threshold1 &&
    threshold2 <= maximum &&
    threshold3 >= threshold2 &&
    threshold3 <= maximum &&
    reset >= 3 &&
    reset <= maximum.max(255) else {
    raise Invalid(0, "invalid coding thresholds or RESET")
  }
  { maximum, threshold1, threshold2, threshold3, reset, }
}

///|
pub fn Interleave::code(self : Interleave) -> Int32 {
  match self {
    None => 0
    Line => 1
    Sample => 2
  }
}

///|
fn interleave_from_code(code : Int32, at : Int32) -> Interleave raise JlsError {
  match code {
    0 => None
    1 => Line
    2 => Sample
    _ => raise Invalid(at, "unknown interleave mode")
  }
}
