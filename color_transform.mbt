// Adapted from CharLS 2.4.2 color_transform.h.
// Copyright (c) Team CharLS. SPDX-License-Identifier: BSD-3-Clause.

///|
/// Reversible HP transforms are a common CharLS extension, not part of T.87.
/// They are restricted here to lossless, full-range 8/16-bit three-channel RGB.
pub(all) enum ColorTransform {
  Identity
  Hp1
  Hp2
  Hp3
} derive(Eq, @debug.Debug)

///|
pub fn ColorTransform::code(self : ColorTransform) -> Int32 {
  match self {
    Identity => 0
    Hp1 => 1
    Hp2 => 2
    Hp3 => 3
  }
}

///|
pub fn ColorTransform::from_code(
  value : Int32,
) -> ColorTransform raise JlsError {
  match value {
    0 => Identity
    1 => Hp1
    2 => Hp2
    3 => Hp3
    _ => raise Unsupported(0, "unknown HP color transform")
  }
}

///|
fn transform_triplet(
  red : Int32,
  green : Int32,
  blue : Int32,
  transform : ColorTransform,
  bits : Int32,
  inverse : Bool,
) -> (Int32, Int32, Int32) {
  let range = 1 << bits
  let mask = range - 1
  let half = range / 2
  if inverse {
    match transform {
      Identity => (red, green, blue)
      Hp1 => ((red + green - half) & mask, green, (blue + green - half) & mask)
      Hp2 => {
        let r = (red + green - half) & mask
        (r, green, (blue + ((r + green) >> 1) - half) & mask)
      }
      Hp3 => {
        let g = red - ((blue + green) >> 2) + range / 4
        ((blue + g - half) & mask, g & mask, (green + g - half) & mask)
      }
    }
  } else {
    match transform {
      Identity => (red, green, blue)
      Hp1 => ((red - green + half) & mask, green, (blue - green + half) & mask)
      Hp2 =>
        (
          (red - green + half) & mask,
          green,
          (blue - ((red + green) >> 1) + half) & mask,
        )
      Hp3 => {
        let b = (blue - green + half) & mask
        let r = (red - green + half) & mask
        ((green + ((b + r) >> 2) - range / 4) & mask, b, r)
      }
    }
  }
}

///|
pub fn Image::color_transform(
  self : Image,
  transform : ColorTransform,
  inverse~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> Image raise JlsError {
  self.validate(limits~)
  if transform == Identity {
    return { ..self, samples: self.samples.copy(), }
  }
  guard self.frame.components == 3 &&
    (self.frame.bits_per_sample == 8 || self.frame.bits_per_sample == 16) else {
    raise Unsupported(0, "HP transforms require full precision RGB8 or RGB16")
  }
  let values = Array::make(self.samples.length(), 0)
  for at = 0; at < self.samples.length(); at = at + 3 {
    let (a, b, c) = transform_triplet(
      self.samples[at],
      self.samples[at + 1],
      self.samples[at + 2],
      transform,
      self.frame.bits_per_sample,
      inverse,
    )
    values[at] = a
    values[at + 1] = b
    values[at + 2] = c
  }
  { frame: self.frame, samples: values, }
}

///|
fn detected_transform(info : Info) -> ColorTransform raise JlsError {
  let mut found : ColorTransform? = None
  for segment in info.metadata {
    if segment.marker == 0xE8 &&
      segment.data.length() >= 4 &&
      segment.data[:4] == b"mrfx"[:] {
      guard found is None && segment.data.length() == 5 else {
        raise Invalid(
          segment.offset,
          "duplicate or malformed HP transform marker",
        )
      }
      found = Some(ColorTransform::from_code(segment.data[4].to_int()))
    }
  }
  let transform = found.unwrap_or(Identity)
  if transform != Identity {
    guard info.frame.components == 3 &&
      (info.frame.bits_per_sample == 8 || info.frame.bits_per_sample == 16) else {
      raise Unsupported(0, "HP transform marker requires RGB8 or RGB16")
    }
    for scan in info.scans {
      guard scan.near == 0 &&
        scan.interleave != None &&
        scan.preset.maximum == (1 << info.frame.bits_per_sample) - 1 else {
        raise Unsupported(
          scan.entropy_offset,
          "HP transforms support lossless full-range interleaved scans only",
        )
      }
    }
  }
  transform
}

///|
pub fn Info::color_transform(self : Info) -> ColorTransform raise JlsError {
  detected_transform(self)
}

///|
pub fn encode_transformed(
  image : Image,
  transform : ColorTransform,
  options~ : EncodeOptions = { ..EncodeOptions::default(), interleave: Sample, },
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  if transform == Identity {
    return encode(image, options~, limits~)
  }
  guard options.near == 0 && options.interleave != None else {
    raise Unsupported(0, "HP encoding requires lossless interleaved mode")
  }
  let preset = options.preset.resolve(image.frame.bits_per_sample, options.near)
  guard preset.maximum == (1 << image.frame.bits_per_sample) - 1 else {
    raise Unsupported(0, "HP encoding requires full-range MAXVAL")
  }
  check_encoding_budget(
    image.frame,
    options,
    preset,
    limits,
    extra_segments=1,
    metadata_bytes=5,
  )
  let transformed = image.color_transform(transform, limits~)
  let wire = encode(transformed, options~, limits~)
  let payload = @buffer.Buffer::Buffer()
  payload.write_bytes(b"mrfx"[:])
  payload.write_byte(transform.code().to_byte())
  let out = @buffer.Buffer::Buffer()
  out.write_bytes(wire[:2])
  append_segment(out, 0xE8, payload.to_bytes()[:], limits.compressed_bytes)
  guard wire.length() - 2 <= limits.compressed_bytes - out.length() else {
    raise Limit(0, "transformed output exceeds byte budget")
  }
  out.write_bytes(wire[2:])
  out.to_bytes()
}
