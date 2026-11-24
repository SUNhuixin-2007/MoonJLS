///|
pub(all) suberror JlsError {
  Invalid(Int32, String)
  Truncated(Int32, String)
  Unsupported(Int32, String)
  Limit(Int32, String)
}

///|
pub fn JlsError::describe(self : JlsError) -> String {
  match self {
    Invalid(p, s) => "invalid JPEG-LS at \{p}: \{s}"
    Truncated(p, s) => "truncated JPEG-LS at \{p}: \{s}"
    Unsupported(p, s) => "unsupported JPEG-LS at \{p}: \{s}"
    Limit(p, s) => "JPEG-LS limit at \{p}: \{s}"
  }
}

///|
pub(all) struct Limits {
  pixels : Int32
  samples : Int32
  compressed_bytes : Int32
  metadata_bytes : Int32
  segments : Int32
} derive(Eq, @debug.Debug)

///|
pub fn Limits::default() -> Limits {
  {
    pixels: 16777216,
    samples: 67108864,
    compressed_bytes: 268435456,
    metadata_bytes: 1048576,
    segments: 4096,
  }
}

///|
pub(all) enum Interleave {
  None
  Line
  Sample
} derive(Eq, @debug.Debug)

///|
pub(all) struct Frame {
  width : Int32
  height : Int32
  bits_per_sample : Int32
  components : Int32
} derive(Eq, @debug.Debug)

///|
/// Canonical row-major, pixel-interleaved unsigned samples, regardless of the
/// codestream's interleave mode. Values stay exact up to unsigned 16 bits.
pub(all) struct Image {
  frame : Frame
  samples : Array[Int32]
} derive(Eq, @debug.Debug)

///|
/// A zero field selects its standard default; resolved presets contain no zeros.
pub(all) struct Preset {
  maximum : Int32
  threshold1 : Int32
  threshold2 : Int32
  threshold3 : Int32
  reset : Int32
} derive(Eq, @debug.Debug)

///|
pub fn Preset::automatic() -> Preset {
  { maximum: 0, threshold1: 0, threshold2: 0, threshold3: 0, reset: 0, }
}

///|
pub(all) struct EncodeOptions {
  near : Int32
  interleave : Interleave
  preset : Preset
} derive(Eq, @debug.Debug)

///|
pub fn EncodeOptions::default() -> EncodeOptions {
  { near: 0, interleave: None, preset: Preset::automatic(), }
}

///|
pub(all) struct Segment {
  marker : Int32
  offset : Int32
  data : Bytes
} derive(Eq, @debug.Debug)

///|
pub(all) struct ScanInfo {
  components : Array[Int32]
  near : Int32
  interleave : Interleave
  preset : Preset
  entropy_offset : Int32
  entropy_end : Int32
  restart_interval : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct Info {
  frame : Frame
  scans : Array[ScanInfo]
  metadata : Array[Segment]
  consumed : Int32
} derive(Eq, @debug.Debug)
