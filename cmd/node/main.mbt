///|
#external
type Host

///|
extern "js" fn read_host(host : Host, offset : String, length : Int32) -> Bytes =
  #| (host, offset, length) => host.read(offset, length)

///|
extern "js" fn write_host(host : Host, bytes : Bytes) -> Int32 =
  #| (host, bytes) => host.write(bytes)

///|
fn send(host : Host, bytes : Bytes) -> Unit raise @jls.JlsError {
  guard write_host(host, bytes) == bytes.length() else {
    raise @jls.Truncated(0, "host returned a short file write")
  }
}

///|
fn source_for(
  host : Host,
  size : String,
) -> @jls.ByteSource raise @jls.JlsError {
  let count = @string.parse_uint64(size[:]) catch {
    _ => raise @jls.Invalid(0, "file size must be an unsigned decimal")
  }
  @jls.ByteSource::new(count, (offset, length) => {
    read_host(host, offset.to_string(), length)
  })
}

///|
fn read_all(source : @jls.ByteSource) -> Bytes raise @jls.JlsError {
  guard source.size() <= @jls.Limits::default().compressed_bytes.to_uint64() else {
    raise @jls.Limit(0, "file exceeds compressed byte budget")
  }
  source.read(0UL, source.size().to_int())
}

///|
fn options_for(
  frame : @jls.Frame,
  maximum : Int32,
  near : Int32,
  mode : Int32,
) -> @jls.EncodeOptions raise @jls.JlsError {
  let interleave : @jls.Interleave = match mode {
    -1 => if frame.components <= 2 { None } else { Sample }
    0 => None
    1 => Line
    2 => Sample
    _ => raise @jls.Invalid(0, "unknown interleave option")
  }
  { near, interleave, preset: { ..@jls.Preset::automatic(), maximum, }, }
}

///|
fn convert(
  host : Host,
  size : String,
  operation : String,
  near : Int32,
  mode : Int32,
  pam : Bool,
) -> Json raise @jls.JlsError {
  let source = source_for(host, size)
  if operation == "encode" {
    let prefix = source.read(0UL, 2)
    if prefix == b"P5" || prefix == b"P6" {
      let input = @jls.PnmSource::open(source)
      let options = options_for(input.frame(), input.maximum(), near, mode)
      let mut bytes = 0
      let streaming = input.frame().components == 1 ||
        options.interleave != None
      if streaming {
        let encoder = @jls.RowEncoder::new(
          input.frame(),
          data => send(host, data),
          options~,
        )
        for y in 0..<input.frame().height {
          encoder.push(input.row(y))
        }
        encoder.finish()
        bytes = encoder.bytes_written()
      } else {
        let data = input.encode(options~)
        send(host, data)
        bytes = data.length()
      }
      return {
        "success": true,
        "operation": operation,
        "frame": input.frame().to_json(),
        "maximum": input.maximum(),
        "written_bytes": bytes,
        "streaming_output": streaming,
        "full_pixel_array": false,
      }
    }
    let data = read_all(source)
    let (image, maximum) = if prefix == b"P7" {
      let input = @jls.parse_pam(data[:])
      (input.image, input.maximum)
    } else {
      let input = @jls.parse_pnm(data[:])
      (input.image, input.maximum)
    }
    let wire = @jls.encode(
      image,
      options=options_for(image.frame, maximum, near, mode),
    )
    send(host, wire)
    return {
      "success": true,
      "operation": operation,
      "frame": image.frame.to_json(),
      "maximum": maximum,
      "written_bytes": wire.length(),
      "streaming_output": false,
      "full_pixel_array": true,
    }
  }
  let data = read_all(source)
  let info = @jls.inspect(data[:])
  guard info.consumed == data.length() else {
    raise @jls.Invalid(info.consumed, "trailing bytes after file codestream")
  }
  if operation == "inspect" {
    return {
      "success": true,
      "operation": operation,
      "entropy_validated": false,
      "info": info.to_json(),
    }
  }
  guard operation == "decode" else {
    raise @jls.Invalid(0, "operation must be encode, decode or inspect")
  }
  let image = @jls.decode(data[:])
  let maximum = info.scans[0].preset.maximum
  for scan in info.scans {
    guard scan.preset.maximum == maximum else {
      raise @jls.Unsupported(
        0, "raster export requires one MAXVAL for all scans",
      )
    }
  }
  let use_pam = pam ||
    (image.frame.components != 1 && image.frame.components != 3)
  let count = if use_pam {
    @jls.write_pam_rows(
      image.frame,
      y => image.row(y),
      bytes => send(host, bytes),
      maximum~,
    )
  } else {
    @jls.write_pnm_rows(
      image.frame,
      y => image.row(y),
      bytes => send(host, bytes),
      maximum~,
    )
  }
  {
    "success": true,
    "operation": operation,
    "frame": image.frame.to_json(),
    "maximum": maximum,
    "written_bytes": count.to_string(),
    "raster_format": if use_pam {
      "P7"
    } else if image.frame.components == 1 {
      "P5"
    } else {
      "P6"
    },
    "full_pixel_array": true,
  }
}

///|
pub fn convert_file(
  host : Host,
  size : String,
  operation : String,
  near : Int32,
  mode : Int32,
  pam : Bool,
) -> String {
  let result = convert(host, size, operation, near, mode, pam) catch {
    error =>
      return Json::object({ "success": false, "error": error.describe() }).stringify()
  }
  result.stringify()
}
