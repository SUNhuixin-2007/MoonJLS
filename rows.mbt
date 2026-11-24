///|
/// Low-memory input contract: for each requested row return only the selected
/// component indices, in pixel-interleaved order. Planar scans may revisit rows.
/// The host must provide stable pixels for the duration of an encoding operation.
pub fn encode_rows(
  frame : Frame,
  row_at : (Int32, Array[Int32]) -> Array[Int32] raise JlsError,
  options~ : EncodeOptions = EncodeOptions::default(),
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  ignore(frame.sample_count(limits~))
  let preset = options.preset.resolve(frame.bits_per_sample, options.near)
  guard frame.components > 1 || options.interleave == None else {
    raise Invalid(0, "single component requires noninterleaved mode")
  }
  check_encoding_budget(frame, options, preset, limits)
  let out = @buffer.Buffer::Buffer()
  out.write_bytes(b"\xff\xd8"[:])
  write_frame(out, frame, limits)
  let defaults = Preset::defaults(
    (1 << frame.bits_per_sample) - 1,
    options.near,
  )
  if preset != defaults {
    write_preset(out, preset, limits)
  }
  let groups : Array[Array[Int32]] = if options.interleave == None {
    Array::makei(frame.components, c => [c])
  } else {
    [Array::makei(frame.components, c => c)]
  }
  for components in groups {
    write_scan_header(out, components, options, limits)
    let entropy = encode_scan_rows(
      frame,
      components,
      preset,
      options.near,
      options.interleave,
      row_at,
      limits,
    )
    guard entropy.length() <= limits.compressed_bytes - out.length() else {
      raise Limit(0, "row encoding exceeds compressed byte budget")
    }
    out.write_bytes(entropy[:])
  }
  guard out.length() <= limits.compressed_bytes - 2 else {
    raise Limit(0, "no space for EOI")
  }
  out.write_bytes(b"\xff\xd9"[:])
  out.to_bytes()
}

///|
/// Reconstructs samples with two rows per scan component, without allocating a
/// full destination image. The compressed source remains resident. Each callback
/// owns a fresh row and component list; later decoder activity cannot modify it.
/// Callbacks are incremental: discard partial output if this function raises.
pub fn decode_rows(
  data : BytesView,
  emit : (Int32, Array[Int32], Array[Int32]) -> Unit raise JlsError,
  limits~ : Limits = Limits::default(),
) -> Info raise JlsError {
  let info = inspect(data, limits~)
  guard info.consumed == data.length() else {
    raise Invalid(info.consumed, "trailing image data")
  }
  ignore(info.spiff_header(limits~))
  let transform = detected_transform(info)
  for scan in info.scans {
    decode_scan_restarted(
      data,
      info.frame,
      scan,
      (row, components, values) => {
        if transform != Identity {
          guard components == [0, 1, 2] else {
            raise Unsupported(
              0, "transformed row requires standard RGB component order",
            )
          }
          for x in 0..<info.frame.width {
            let at = x * 3
            let (r, g, b) = transform_triplet(
              values[at],
              values[at + 1],
              values[at + 2],
              transform,
              info.frame.bits_per_sample,
              true,
            )
            values[at] = r
            values[at + 1] = g
            values[at + 2] = b
          }
        }
        emit(row, components, values)
      },
      limits,
    )
  }
  info
}
