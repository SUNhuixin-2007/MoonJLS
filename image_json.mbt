///|
/// Tagged image interchange keeps sample precision and component order explicit.
/// Every unsigned 16-bit sample is exactly representable by a JSON number.
pub fn Image::to_json(self : Image) -> Json {
  {
    "format": "moonjls.image.v1",
    "frame": self.frame.to_json(),
    "samples": Json::array(
      self.samples.map(value => Json::number(value.to_double())),
    ),
  }
}

///|
pub fn Image::from_json(
  json : Json,
  limits~ : Limits = Limits::default(),
) -> Image raise JlsError {
  check_limits(limits)
  let object = image_json_object(json)
  image_json_fields(object, ["format", "frame", "samples"])
  guard image_json_string(image_json_field(object, "format")) ==
    "moonjls.image.v1" else {
    raise Unsupported(0, "unknown image JSON format")
  }
  let frame = Frame::from_json(image_json_field(object, "frame"), limits~)
  let values = image_json_array(image_json_field(object, "samples"))
  let count = frame.sample_count(limits~)
  guard values.length() == count else {
    raise Invalid(0, "JSON samples disagree with image dimensions")
  }
  let maximum = (1 << frame.bits_per_sample) - 1
  let samples : Array[Int32] = []
  for value in values {
    samples.push(image_json_integer(value, 0, maximum))
  }
  { frame, samples, }
}

///|
pub fn Frame::to_json(self : Frame) -> Json {
  {
    "width": self.width,
    "height": self.height,
    "bits_per_sample": self.bits_per_sample,
    "components": self.components,
  }
}

///|
pub fn Frame::from_json(
  json : Json,
  limits~ : Limits = Limits::default(),
) -> Frame raise JlsError {
  let object = image_json_object(json)
  image_json_fields(object, ["width", "height", "bits_per_sample", "components"])
  let frame = {
    width: image_json_integer(image_json_field(object, "width"), 1, 2147483647),
    height: image_json_integer(
      image_json_field(object, "height"),
      1,
      2147483647,
    ),
    bits_per_sample: image_json_integer(
      image_json_field(object, "bits_per_sample"),
      2,
      16,
    ),
    components: image_json_integer(image_json_field(object, "components"), 1, 4),
  }
  ignore(frame.sample_count(limits~))
  frame
}

///|
pub fn Preset::to_json(self : Preset) -> Json {
  {
    "maximum": self.maximum,
    "threshold1": self.threshold1,
    "threshold2": self.threshold2,
    "threshold3": self.threshold3,
    "reset": self.reset,
  }
}

///|
/// Reads the raw zero-means-default preset. Resolution against precision and
/// NEAR remains mandatory before using it for a scan.
pub fn Preset::from_json(json : Json) -> Preset raise JlsError {
  let object = image_json_object(json)
  image_json_fields(object, [
    "maximum", "threshold1", "threshold2", "threshold3", "reset",
  ])
  {
    maximum: image_json_integer(image_json_field(object, "maximum"), 0, 65535),
    threshold1: image_json_integer(
      image_json_field(object, "threshold1"),
      0,
      65535,
    ),
    threshold2: image_json_integer(
      image_json_field(object, "threshold2"),
      0,
      65535,
    ),
    threshold3: image_json_integer(
      image_json_field(object, "threshold3"),
      0,
      65535,
    ),
    reset: image_json_integer(image_json_field(object, "reset"), 0, 65535),
  }
}

///|
pub fn EncodeOptions::to_json(self : EncodeOptions) -> Json {
  {
    "format": "moonjls.options.v1",
    "near": self.near,
    "interleave": self.interleave.code(),
    "preset": self.preset.to_json(),
  }
}

///|
pub fn EncodeOptions::from_json(json : Json) -> EncodeOptions raise JlsError {
  let object = image_json_object(json)
  image_json_fields(object, ["format", "near", "interleave", "preset"])
  guard image_json_string(image_json_field(object, "format")) ==
    "moonjls.options.v1" else {
    raise Unsupported(0, "unknown options JSON format")
  }
  {
    near: image_json_integer(image_json_field(object, "near"), 0, 255),
    interleave: interleave_from_code(
      image_json_integer(image_json_field(object, "interleave"), 0, 2),
      0,
    ),
    preset: Preset::from_json(image_json_field(object, "preset")),
  }
}

///|
pub fn PixelLayout::to_json(self : PixelLayout) -> Json {
  {
    "order": if self.order == Planar {
      "planar"
    } else {
      "interleaved"
    },
    "storage": match self.storage {
      U8 => "u8"
      U16Big => "u16be"
      U16Little => "u16le"
    },
    "row_stride": self.row_stride,
    "plane_stride": self.plane_stride,
  }
}

///|
/// Structural decoding only; packed_size(frame) verifies nonoverlap and budgets.
pub fn PixelLayout::from_json(json : Json) -> PixelLayout raise JlsError {
  let object = image_json_object(json)
  image_json_fields(object, ["order", "storage", "row_stride", "plane_stride"])
  let order = match image_json_string(image_json_field(object, "order")) {
    "planar" => Planar
    "interleaved" => Interleaved
    _ => raise Invalid(0, "unknown pixel order")
  }
  let storage = match image_json_string(image_json_field(object, "storage")) {
    "u8" => U8
    "u16be" => U16Big
    "u16le" => U16Little
    _ => raise Invalid(0, "unknown sample storage")
  }
  {
    order,
    storage,
    row_stride: image_json_integer(
      image_json_field(object, "row_stride"),
      0,
      2147483647,
    ),
    plane_stride: image_json_integer(
      image_json_field(object, "plane_stride"),
      0,
      2147483647,
    ),
  }
}

///|
pub fn ErrorMetrics::to_json(self : ErrorMetrics) -> Json {
  {
    "samples": self.samples,
    "maximum_error": self.maximum_error,
    "mean_error": self.mean_error,
    "mean_absolute_error": self.mean_absolute_error,
    "mean_squared_error": self.mean_squared_error,
    "channels": Json::array(
      self.channels.map(channel => {
        "component": channel.component,
        "samples": channel.samples,
        "maximum_error": channel.maximum_error,
        "mean_error": channel.mean_error,
        "mean_absolute_error": channel.mean_absolute_error,
        "mean_squared_error": channel.mean_squared_error,
      }),
    ),
  }
}

///|
fn image_json_object(json : Json) -> Map[String, Json] raise JlsError {
  match json {
    Object(value) => value
    _ => raise Invalid(0, "expected image JSON object")
  }
}

///|
fn image_json_array(json : Json) -> Array[Json] raise JlsError {
  match json {
    Array(value) => value
    _ => raise Invalid(0, "expected image JSON array")
  }
}

///|
fn image_json_string(json : Json) -> String raise JlsError {
  match json {
    String(value) => value
    _ => raise Invalid(0, "expected image JSON string")
  }
}

///|
fn image_json_field(
  object : Map[String, Json],
  name : String,
) -> Json raise JlsError {
  match object.get(name) {
    Some(value) => value
    None => raise Invalid(0, "missing image JSON field: " + name)
  }
}

///|
fn image_json_fields(
  object : Map[String, Json],
  fields : Array[String],
) -> Unit raise JlsError {
  guard object.length() == fields.length() else {
    raise Invalid(0, "unexpected or missing image JSON fields")
  }
  for name in fields {
    ignore(image_json_field(object, name))
  }
}

///|
fn image_json_integer(
  json : Json,
  minimum : Int32,
  maximum : Int32,
) -> Int32 raise JlsError {
  match json {
    Number(value, ..) => {
      guard value >= minimum.to_double() &&
        value <= maximum.to_double() &&
        value == value.floor() else {
        raise Invalid(0, "image JSON integer is fractional or out of range")
      }
      value.to_int()
    }
    _ => raise Invalid(0, "expected image JSON integer")
  }
}
