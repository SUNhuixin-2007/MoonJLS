///|
fn json_field(
  object : Map[String, Json],
  name : String,
) -> Json raise @jls.JlsError {
  match object.get(name) {
    Some(value) => value
    None => raise @jls.Invalid(0, "missing bridge field: " + name)
  }
}

///|
fn object_value(json : Json) -> Map[String, Json] raise @jls.JlsError {
  match json {
    Object(value) => value
    _ => raise @jls.Invalid(0, "bridge expects an object")
  }
}

///|
fn integer(json : Json, maximum : Int32) -> Int32 raise @jls.JlsError {
  match json {
    Number(value, ..) => {
      guard value >= 0.0 &&
        value <= maximum.to_double() &&
        value == value.floor() else {
        raise @jls.Invalid(0, "bridge integer out of range")
      }
      value.to_int()
    }
    _ => raise @jls.Invalid(0, "bridge expects an integer")
  }
}

///|
fn text(json : Json) -> String raise @jls.JlsError {
  match json {
    String(value) => value
    _ => raise @jls.Invalid(0, "bridge expects a string")
  }
}

///|
fn image_value(object : Map[String, Json]) -> @jls.Image raise @jls.JlsError {
  let frame : @jls.Frame = {
    width: integer(json_field(object, "width"), 2147483645),
    height: integer(json_field(object, "height"), 2147483647),
    bits_per_sample: integer(json_field(object, "bits"), 16),
    components: integer(json_field(object, "components"), 4),
  }
  let expected = frame.sample_count()
  if object.get("fill") is Some(value) {
    return { frame, samples: Array::make(expected, integer(value, 65535)), }
  }
  let values = match json_field(object, "samples") {
    Array(value) => value
    _ => raise @jls.Invalid(0, "bridge samples must be an array")
  }
  guard values.length() == expected else {
    raise @jls.Invalid(0, "bridge sample count mismatch")
  }
  { frame, samples: values.map(value => integer(value, 65535)), }
}

///|
fn image_json(image : @jls.Image) -> Json {
  {
    "width": image.frame.width,
    "height": image.frame.height,
    "bits": image.frame.bits_per_sample,
    "components": image.frame.components,
    "samples": Json::array(image.samples.map(x => Json::number(x.to_double()))),
  }
}

///|
fn execute(operation : String, input : Json) -> Json raise @jls.JlsError {
  let object = object_value(input)
  match operation {
    "encode" => {
      let interleave : @jls.Interleave = match
        integer(json_field(object, "interleave"), 2) {
        0 => None
        1 => Line
        _ => Sample
      }
      let preset = match object.get("preset") {
        Some(value) => @jls.Preset::from_json(value)
        None => @jls.Preset::automatic()
      }
      let options : @jls.EncodeOptions = {
        preset,
        near: integer(json_field(object, "near"), 255),
        interleave,
      }
      let transform = match object.get("transform") {
        Some(value) => @jls.ColorTransform::from_code(integer(value, 3))
        None => @jls.ColorTransform::Identity
      }
      let image = image_value(object)
      let bytes = match object.get("restart") {
        Some(value) =>
          @jls.encode_restarted(image, integer(value, 65535), options~)
        None =>
          match object.get("encoder") {
            Some(String("push")) => {
              let out = @buffer.Buffer::Buffer()
              let encoder = @jls.RowEncoder::new(
                image.frame,
                b => out.write_bytes(b[:]),
                options~,
              )
              for y in 0..<image.frame.height {
                encoder.push(image.row(y))
              }
              encoder.finish()
              out.to_bytes()
            }
            _ => @jls.encode_transformed(image, transform, options~)
          }
      }
      let bytes = if object.get("spiff") == Some(Json::boolean(true)) {
        @jls.with_spiff(bytes[:], @jls.SpiffHeader::default(image.frame))
      } else {
        bytes
      }
      { "hex": @jls.hex_encode(bytes[:]) }
    }
    "decode" => {
      let data = @jls.hex_decode(text(json_field(object, "hex")))
      image_json(@jls.decode(data[:]))
    }
    "inspect" => {
      let data = @jls.hex_decode(text(json_field(object, "hex")))
      @jls.inspect(data[:]).to_json()
    }
    _ =>
      raise @jls.Invalid(
        0, "bridge operation must be encode, decode or inspect",
      )
  }
}

///|
fn main {
  let args = @env.args()
  let mut start = -1
  for i in 0..<args.length() {
    if args[i] == "encode" || args[i] == "decode" || args[i] == "inspect" {
      start = i
      break
    }
  }
  if start < 0 || args.length() != start + 2 {
    println("{\"error\":\"usage: interop OP JSON\"}")
    return
  }
  let input = @json.parse(
    args[start + 1][:],
    max_nesting_depth=16,
    reject_duplicate_keys=true,
  ) catch {
    _ => {
      println("{\"error\":\"invalid bridge JSON\"}")
      return
    }
  }
  let result = execute(args[start], input) catch {
    error => {
      println(Json::object({ "error": error.describe() }).stringify())
      return
    }
  }
  println(result.stringify())
}
