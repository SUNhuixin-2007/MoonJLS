///|
pub(all) struct Region {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
} derive(Eq, @debug.Debug)

///|
pub fn Region::full(frame : Frame) -> Region {
  { x: 0, y: 0, width: frame.width, height: frame.height, }
}

///|
pub fn Region::validate(self : Region, frame : Frame) -> Unit raise JlsError {
  guard self.x >= 0 &&
    self.y >= 0 &&
    self.width > 0 &&
    self.height > 0 &&
    self.x <= frame.width &&
    self.y <= frame.height &&
    self.width <= frame.width - self.x &&
    self.height <= frame.height - self.y else {
    raise Invalid(0, "region must be a nonempty rectangle inside the frame")
  }
}

///|
pub fn Region::intersection(
  self : Region,
  other : Region,
) -> Region? raise JlsError {
  guard self.x >= 0 &&
    self.y >= 0 &&
    self.width > 0 &&
    self.height > 0 &&
    other.x >= 0 &&
    other.y >= 0 &&
    other.width > 0 &&
    other.height > 0 else {
    raise Invalid(0, "invalid region rectangle")
  }
  let left = self.x.max(other.x)
  let top = self.y.max(other.y)
  let right = (self.x.to_int64() + self.width.to_int64()).min(
    other.x.to_int64() + other.width.to_int64(),
  )
  let bottom = (self.y.to_int64() + self.height.to_int64()).min(
    other.y.to_int64() + other.height.to_int64(),
  )
  if right <= left.to_int64() || bottom <= top.to_int64() {
    None
  } else {
    Some({
      x: left,
      y: top,
      width: (right - left.to_int64()).to_int(),
      height: (bottom - top.to_int64()).to_int(),
    })
  }
}

///|
pub fn Region::to_json(self : Region) -> Json {
  { "x": self.x, "y": self.y, "width": self.width, "height": self.height }
}

///|
pub fn Region::from_json(json : Json, frame : Frame) -> Region raise JlsError {
  let object = image_json_object(json)
  image_json_fields(object, ["x", "y", "width", "height"])
  let region = {
    x: image_json_integer(image_json_field(object, "x"), 0, frame.width),
    y: image_json_integer(image_json_field(object, "y"), 0, frame.height),
    width: image_json_integer(image_json_field(object, "width"), 1, frame.width),
    height: image_json_integer(
      image_json_field(object, "height"),
      1,
      frame.height,
    ),
  }
  region.validate(frame)
  region
}

///|
/// JPEG-LS prediction prevents arbitrary entropy seeking. This decodes the entire
/// image's scans but retains only the requested pixel rectangle and channels.
/// Memory is proportional to scan row width plus the selected output rectangle.
pub fn decode_region(
  data : BytesView,
  region : Region,
  components? : Array[Int32],
  limits~ : Limits = Limits::default(),
) -> Image raise JlsError {
  let info = inspect(data, limits~)
  region.validate(info.frame)
  let selected = components.unwrap_or(
    Array::makei(info.frame.components, c => c),
  )
  validate_scan_components(
    info.frame,
    selected,
    if selected.length() == 1 {
      None
    } else {
      Line
    },
  )
  let frame = {
    width: region.width,
    height: region.height,
    bits_per_sample: info.frame.bits_per_sample,
    components: selected.length(),
  }
  let samples = Array::make(frame.sample_count(limits~), 0)
  ignore(
    decode_rows(
      data,
      (y, scan_components, row) => {
        if y >= region.y && y - region.y < region.height {
          for c in 0..<scan_components.length() {
            let mut destination = -1
            for i in 0..<selected.length() {
              if selected[i] == scan_components[c] {
                destination = i
              }
            }
            if destination >= 0 {
              for x in 0..<region.width {
                samples[((y - region.y) * region.width + x) * selected.length() +
                destination] = row[(region.x + x) * scan_components.length() + c]
              }
            }
          }
        }
      },
      limits~,
    ),
  )
  { frame, samples, }
}

///|
/// Plans a bounded nonoverlapping partition without decoding or copying pixels.
pub fn tile_regions(
  frame : Frame,
  tile_width : Int32,
  tile_height : Int32,
  maximum_tiles~ : Int32 = 65536,
) -> Array[Region] raise JlsError {
  guard frame.width > 0 &&
    frame.height > 0 &&
    tile_width > 0 &&
    tile_height > 0 &&
    maximum_tiles >= 0 else {
    raise Invalid(0, "invalid tile dimensions or count budget")
  }
  let columns = 1 + (frame.width - 1) / tile_width
  let rows = 1 + (frame.height - 1) / tile_height
  guard columns <= maximum_tiles / rows else {
    raise Limit(0, "tile count exceeds budget")
  }
  let result : Array[Region] = []
  for r in 0..<rows {
    let y = r * tile_height
    for c in 0..<columns {
      let x = c * tile_width
      result.push({
        x,
        y,
        width: tile_width.min(frame.width - x),
        height: tile_height.min(frame.height - y),
      })
    }
  }
  result
}
