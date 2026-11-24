///|
/// Marker counts match inspect: SOI is excluded, EOI and restart markers count.
/// Check before callbacks or allocation of scan buffers can produce side effects.
fn check_encoding_budget(
  frame : Frame,
  options : EncodeOptions,
  preset : Preset,
  limits : Limits,
  restart_interval~ : Int32 = 0,
  extra_segments~ : Int32 = 0,
  metadata_bytes~ : Int32 = 0,
) -> Unit raise JlsError {
  ignore(frame.sample_count(limits~))
  let scans = if options.interleave == None { frame.components } else { 1 }
  let mut markers = 2 + scans + extra_segments
  if frame.width > 65535 || frame.height > 65535 {
    markers += 1
  }
  if preset != Preset::defaults((1 << frame.bits_per_sample) - 1, options.near) {
    markers += 1
  }
  if restart_interval > 0 {
    markers += 1
  }
  guard markers <= limits.segments && metadata_bytes <= limits.metadata_bytes else {
    raise Limit(0, "encoding headers exceed segment or metadata budget")
  }
  if restart_interval > 0 {
    let per_scan = (frame.height - 1) / restart_interval
    guard per_scan <= (limits.segments - markers) / scans else {
      raise Limit(0, "encoding restart markers exceed segment budget")
    }
  }
}
