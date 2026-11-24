///|
pub(all) enum PixelOrder {
  Interleaved
  Planar
} derive(Eq, @debug.Debug)

///|
pub(all) enum SampleStorage {
  U8
  U16Big
  U16Little
} derive(Eq, @debug.Debug)

///|
/// A zero stride selects tight packing. For planar buffers plane_stride selects
/// the distance between channel starts; all byte offsets are nonnegative.
pub(all) struct PixelLayout {
  order : PixelOrder
  storage : SampleStorage
  row_stride : Int32
  plane_stride : Int32
} derive(Eq, @debug.Debug)

///|
pub fn PixelLayout::tight(
  storage~ : SampleStorage = U8,
  order~ : PixelOrder = Interleaved,
) -> PixelLayout {
  { order, storage, row_stride: 0, plane_stride: 0, }
}

///|
pub fn SampleStorage::bytes(self : SampleStorage) -> Int32 {
  match self {
    U8 => 1
    U16Big | U16Little => 2
  }
}

///|
priv struct ResolvedLayout {
  row_stride : Int32
  plane_stride : Int32
  sample_bytes : Int32
  span : Int32
}

///|
fn image_layout(
  frame : Frame,
  layout : PixelLayout,
  limits : Limits,
) -> ResolvedLayout raise JlsError {
  ignore(frame.sample_count(limits~))
  guard layout.row_stride >= 0 && layout.plane_stride >= 0 else {
    raise Invalid(0, "pixel strides must be nonnegative")
  }
  let sample_bytes = layout.storage.bytes()
  guard frame.bits_per_sample <= sample_bytes * 8 else {
    raise Invalid(0, "sample storage cannot preserve image precision")
  }
  let row_samples = frame.width *
    (if layout.order == Interleaved { frame.components } else { 1 })
  let row_bytes = row_samples * sample_bytes
  let row_stride = if layout.row_stride == 0 {
    row_bytes
  } else {
    layout.row_stride
  }
  guard row_stride >= row_bytes else {
    raise Invalid(0, "row stride is smaller than active samples")
  }
  let full_plane = row_stride.to_int64() * frame.height.to_int64()
  let plane_stride = if layout.order == Interleaved {
    guard layout.plane_stride == 0 else {
      raise Invalid(0, "interleaved layout has no plane stride")
    }
    0
  } else {
    let stride = if layout.plane_stride == 0 {
      full_plane
    } else {
      layout.plane_stride.to_int64()
    }
    guard stride >= full_plane && stride <= limits.compressed_bytes.to_int64() else {
      raise Invalid(0, "plane stride overlaps rows or exceeds byte budget")
    }
    stride.to_int()
  }
  let span = (frame.height - 1).to_int64() * row_stride.to_int64() +
    row_bytes.to_int64() +
    (if layout.order == Planar {
      (frame.components - 1).to_int64() * plane_stride.to_int64()
    } else {
      0L
    })
  guard span <= limits.compressed_bytes.to_int64() else {
    raise Limit(0, "packed image exceeds byte budget")
  }
  { row_stride, plane_stride, sample_bytes, span: span.to_int(), }
}

///|
/// Minimum buffer span containing every active sample. A final padding row is
/// not required; internal row and plane padding still contributes to this span.
pub fn Frame::packed_size(
  self : Frame,
  layout : PixelLayout,
  limits~ : Limits = Limits::default(),
) -> Int32 raise JlsError {
  image_layout(self, layout, limits).span
}

///|
fn image_byte_offset(
  frame : Frame,
  layout : PixelLayout,
  resolved : ResolvedLayout,
  x : Int32,
  y : Int32,
  component : Int32,
) -> Int32 {
  y * resolved.row_stride +
  (if layout.order == Planar {
    component * resolved.plane_stride + x * resolved.sample_bytes
  } else {
    (x * frame.components + component) * resolved.sample_bytes
  })
}

///|
pub fn Image::from_packed(
  frame : Frame,
  data : BytesView,
  layout~ : PixelLayout = PixelLayout::tight(),
  limits~ : Limits = Limits::default(),
) -> Image raise JlsError {
  let resolved = image_layout(frame, layout, limits)
  guard data.length() <= limits.compressed_bytes else {
    raise Limit(0, "packed input exceeds byte budget")
  }
  guard data.length() >= resolved.span else {
    raise Truncated(data.length(), "packed buffer misses active samples")
  }
  let count = frame.sample_count(limits~)
  let samples = Array::make(count, 0)
  let maximum = (1 << frame.bits_per_sample) - 1
  for y in 0..<frame.height {
    for x in 0..<frame.width {
      for component in 0..<frame.components {
        let offset = image_byte_offset(frame, layout, resolved, x, y, component)
        let value = match layout.storage {
          U8 => data[offset].to_int()
          U16Big => (data[offset].to_int() << 8) | data[offset + 1].to_int()
          U16Little => data[offset].to_int() | (data[offset + 1].to_int() << 8)
        }
        guard value <= maximum else {
          raise Invalid(offset, "packed sample exceeds declared precision")
        }
        samples[(y * frame.width + x) * frame.components + component] = value
      }
    }
  }
  { frame, samples, }
}

///|
/// Produces the minimum containing span and initializes all internal padding to
/// zero. Neither byte order nor planar packing changes numeric sample values.
pub fn Image::to_packed(
  self : Image,
  layout~ : PixelLayout = PixelLayout::tight(),
  limits~ : Limits = Limits::default(),
) -> Bytes raise JlsError {
  self.validate(limits~)
  let resolved = image_layout(self.frame, layout, limits)
  let bytes = Array::make(resolved.span, b'\x00')
  for y in 0..<self.frame.height {
    for x in 0..<self.frame.width {
      for component in 0..<self.frame.components {
        let offset = image_byte_offset(
          self.frame,
          layout,
          resolved,
          x,
          y,
          component,
        )
        let value = self.samples[(y * self.frame.width + x) *
          self.frame.components +
          component]
        match layout.storage {
          U8 => bytes[offset] = value.to_byte()
          U16Big => {
            bytes[offset] = (value >> 8).to_byte()
            bytes[offset + 1] = value.to_byte()
          }
          U16Little => {
            bytes[offset] = value.to_byte()
            bytes[offset + 1] = (value >> 8).to_byte()
          }
        }
      }
    }
  }
  Bytes::from_array(bytes)
}

///|
pub fn Image::sample(
  self : Image,
  x : Int32,
  y : Int32,
  component~ : Int32 = 0,
  limits~ : Limits = Limits::default(),
) -> Int32 raise JlsError {
  let count = self.frame.sample_count(limits~)
  guard self.samples.length() == count else {
    raise Invalid(0, "sample count disagrees with frame")
  }
  guard x >= 0 &&
    x < self.frame.width &&
    y >= 0 &&
    y < self.frame.height &&
    component >= 0 &&
    component < self.frame.components else {
    raise Invalid(0, "sample coordinate outside frame")
  }
  let index = (y * self.frame.width + x) * self.frame.components + component
  let value = self.samples[index]
  guard value >= 0 && value < 1 << self.frame.bits_per_sample else {
    raise Invalid(index, "sample exceeds declared precision")
  }
  value
}

///|
pub fn Image::row(
  self : Image,
  y : Int32,
  limits~ : Limits = Limits::default(),
) -> Array[Int32] raise JlsError {
  guard self.samples.length() == self.frame.sample_count(limits~) else {
    raise Invalid(0, "sample count disagrees with frame")
  }
  guard y >= 0 && y < self.frame.height else {
    raise Invalid(0, "row outside image")
  }
  let width = self.frame.width * self.frame.components
  let row = self.samples[y * width:y * width + width].to_owned()
  for value in row {
    guard value >= 0 && value < 1 << self.frame.bits_per_sample else {
      raise Invalid(y, "row sample exceeds declared precision")
    }
  }
  row
}

///|
pub fn Image::crop(
  self : Image,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
  limits~ : Limits = Limits::default(),
) -> Image raise JlsError {
  self.validate(limits~)
  guard x >= 0 &&
    y >= 0 &&
    x < self.frame.width &&
    y < self.frame.height &&
    width > 0 &&
    width <= self.frame.width - x &&
    height > 0 &&
    height <= self.frame.height - y else {
    raise Invalid(0, "crop rectangle outside image")
  }
  let frame = { ..self.frame, width, height, }
  let samples : Array[Int32] = []
  for row in y..<(y + height) {
    let begin = (row * self.frame.width + x) * frame.components
    for i in begin..<(begin + width * frame.components) {
      samples.push(self.samples[i])
    }
  }
  { frame, samples, }
}

///|
pub fn Image::plane(
  self : Image,
  component : Int32,
  limits~ : Limits = Limits::default(),
) -> Image raise JlsError {
  self.validate(limits~)
  guard component >= 0 && component < self.frame.components else {
    raise Invalid(0, "component outside image")
  }
  let frame = { ..self.frame, components: 1, }
  let samples : Array[Int32] = []
  let pixels = frame.width * frame.height
  for i in 0..<pixels {
    samples.push(self.samples[i * self.frame.components + component])
  }
  { frame, samples, }
}

///|
pub fn merge_planes(
  planes : ArrayView[Image],
  limits~ : Limits = Limits::default(),
) -> Image raise JlsError {
  check_limits(limits)
  guard planes.length() >= 1 && planes.length() <= 4 else {
    raise Invalid(0, "one to four planes are required")
  }
  let first = planes[0]
  first.validate(limits~)
  guard first.frame.components == 1 else {
    raise Invalid(0, "merge requires single-component planes")
  }
  for image in planes {
    image.validate(limits~)
    guard image.frame == first.frame else {
      raise Invalid(0, "plane dimensions or precision disagree")
    }
  }
  let frame = { ..first.frame, components: planes.length(), }
  let count = frame.sample_count(limits~)
  let samples = Array::make(count, 0)
  for i in 0..<first.samples.length() {
    for component in 0..<planes.length() {
      samples[i * planes.length() + component] = planes[component].samples[i]
    }
  }
  { frame, samples, }
}

///|
pub fn Image::with_plane(
  self : Image,
  component : Int32,
  plane : Image,
  limits~ : Limits = Limits::default(),
) -> Image raise JlsError {
  self.validate(limits~)
  plane.validate(limits~)
  guard component >= 0 && component < self.frame.components else {
    raise Invalid(0, "component outside image")
  }
  guard plane.frame == { ..self.frame, components: 1, } else {
    raise Invalid(0, "replacement plane dimensions or precision disagree")
  }
  let samples = self.samples.copy()
  for i in 0..<plane.samples.length() {
    samples[i * self.frame.components + component] = plane.samples[i]
  }
  { frame: self.frame, samples, }
}

///|
pub(all) struct ChannelMetrics {
  component : Int32
  samples : Int32
  maximum_error : Int32
  mean_error : Double
  mean_absolute_error : Double
  mean_squared_error : Double
} derive(Eq, @debug.Debug)

///|
pub(all) struct ErrorMetrics {
  samples : Int32
  maximum_error : Int32
  mean_error : Double
  mean_absolute_error : Double
  mean_squared_error : Double
  channels : Array[ChannelMetrics]
} derive(Eq, @debug.Debug)

///|
/// Exact integer differences are accumulated as binary64 sums; the maximum
/// absolute error is exact. No implicit precision or color conversion occurs.
pub fn compare_images(
  expected : Image,
  actual : Image,
  limits~ : Limits = Limits::default(),
) -> ErrorMetrics raise JlsError {
  expected.validate(limits~)
  actual.validate(limits~)
  guard expected.frame == actual.frame else {
    raise Invalid(0, "comparison needs matching image frames")
  }
  let components = expected.frame.components
  let channels : Array[ChannelMetrics] = []
  let mut maximum_error = 0
  let mut total = 0.0
  let mut absolute = 0.0
  let mut squared = 0.0
  let pixels = expected.frame.width * expected.frame.height
  for component in 0..<components {
    let mut channel_maximum = 0
    let mut channel_total = 0.0
    let mut channel_absolute = 0.0
    let mut channel_squared = 0.0
    for pixel in 0..<pixels {
      let index = pixel * components + component
      let difference = actual.samples[index] - expected.samples[index]
      let magnitude = difference.abs()
      channel_maximum = channel_maximum.max(magnitude)
      channel_total += difference.to_double()
      channel_absolute += magnitude.to_double()
      channel_squared += difference.to_double() * difference.to_double()
    }
    let divisor = pixels.to_double()
    channels.push({
      component,
      samples: pixels,
      maximum_error: channel_maximum,
      mean_error: channel_total / divisor,
      mean_absolute_error: channel_absolute / divisor,
      mean_squared_error: channel_squared / divisor,
    })
    maximum_error = maximum_error.max(channel_maximum)
    total += channel_total
    absolute += channel_absolute
    squared += channel_squared
  }
  let count = expected.samples.length()
  let divisor = count.to_double()
  {
    samples: count,
    maximum_error,
    mean_error: total / divisor,
    mean_absolute_error: absolute / divisor,
    mean_squared_error: squared / divisor,
    channels,
  }
}

///|
pub fn ErrorMetrics::within_near(
  self : ErrorMetrics,
  near : Int32,
) -> Bool raise JlsError {
  guard near >= 0 && near <= 255 else {
    raise Invalid(0, "NEAR must be in 0..255")
  }
  self.maximum_error <= near
}

///|
pub fn verify_near(
  expected : Image,
  actual : Image,
  near : Int32,
  limits~ : Limits = Limits::default(),
) -> ErrorMetrics raise JlsError {
  guard near >= 0 && near <= 255 else {
    raise Invalid(0, "NEAR must be in 0..255")
  }
  let metrics = compare_images(expected, actual, limits~)
  guard metrics.maximum_error <= near else {
    raise Invalid(0, "decoded image exceeds requested NEAR bound")
  }
  metrics
}

///|
/// Copies selected channels into a caller-owned reusable row buffer. Validation
/// completes before the destination is touched, so failed calls are atomic.
pub fn Image::copy_row_into(
  self : Image,
  y : Int32,
  destination : Array[Int32],
  components? : Array[Int32],
  limits~ : Limits = Limits::default(),
) -> Unit raise JlsError {
  guard self.samples.length() == self.frame.sample_count(limits~) else {
    raise Invalid(0, "sample count disagrees with frame")
  }
  guard y >= 0 && y < self.frame.height else {
    raise Invalid(y, "row outside image")
  }
  let selected = components.unwrap_or(
    Array::makei(self.frame.components, c => c),
  )
  validate_scan_components(
    self.frame,
    selected,
    if selected.length() == 1 {
      None
    } else {
      Line
    },
  )
  guard destination.length() == self.frame.width * selected.length() else {
    raise Invalid(y, "destination row sample count disagrees with selection")
  }
  let maximum = (1 << self.frame.bits_per_sample) - 1
  for x in 0..<self.frame.width {
    let source_at = (y * self.frame.width + x) * self.frame.components
    for component in selected {
      let value = self.samples[source_at + component]
      guard value >= 0 && value <= maximum else {
        raise Invalid(source_at + component, "row sample exceeds precision")
      }
    }
  }
  // One pixel of scratch permits in-place channel permutations on one row.
  let pixel = Array::make(selected.length(), 0)
  for x in 0..<self.frame.width {
    let source_at = (y * self.frame.width + x) * self.frame.components
    for c in 0..<selected.length() {
      pixel[c] = self.samples[source_at + selected[c]]
    }
    for c in 0..<selected.length() {
      destination[x * selected.length() + c] = pixel[c]
    }
  }
}
