///|
pub(all) struct SampleSummary {
  samples : Int32
  minimum : Int32
  maximum : Int32
  distinct : Int32
  most_frequent : Int32
  mean : Double
  variance : Double
  entropy_bits : Double
} derive(Eq, @debug.Debug)

///|
/// Incremental exact integer histograms. Marginal entropy is descriptive; it is
/// not a promise about JPEG-LS's contextual compressed size or a quality score.
pub struct SampleHistogram {
  bits : Int32
  components : Int32
  maximum_samples : Int32
  bins : Array[Array[Int32]]
  mut total : Int32
}

///|
pub fn SampleHistogram::new(
  bits : Int32,
  components : Int32,
  maximum_samples~ : Int32 = 67108864,
) -> SampleHistogram raise JlsError {
  guard bits >= 2 &&
    bits <= 16 &&
    components >= 1 &&
    components <= 4 &&
    maximum_samples > 0 else {
    raise Invalid(0, "invalid histogram precision, components or budget")
  }
  {
    bits,
    components,
    maximum_samples,
    bins: Array::makei(components, _ => Array::make(1 << bits, 0)),
    total: 0,
  }
}

///|
/// A rejected row changes no bins; callers may correct it and retry.
pub fn SampleHistogram::push(
  self : SampleHistogram,
  samples : ArrayView[Int32],
) -> Unit raise JlsError {
  guard samples.length() % self.components == 0 else {
    raise Invalid(0, "histogram row does not contain whole pixels")
  }
  guard samples.length() <= self.maximum_samples - self.total else {
    raise Limit(0, "histogram sample budget exceeded")
  }
  let maximum = (1 << self.bits) - 1
  for value in samples {
    guard value >= 0 && value <= maximum else {
      raise Invalid(0, "histogram sample exceeds precision")
    }
  }
  for i in 0..<samples.length() {
    self.bins[i % self.components][samples[i]] += 1
  }
  self.total += samples.length()
}

///|
pub fn SampleHistogram::push_image(
  self : SampleHistogram,
  image : Image,
  limits~ : Limits = Limits::default(),
) -> Unit raise JlsError {
  image.validate(limits~)
  guard image.frame.components == self.components &&
    image.frame.bits_per_sample == self.bits else {
    raise Invalid(0, "image and histogram formats differ")
  }
  self.push(image.samples[:])
}

///|
pub fn SampleHistogram::sample_count(self : SampleHistogram) -> Int32 {
  self.total
}

///|
pub fn SampleHistogram::count(
  self : SampleHistogram,
  component : Int32,
  value : Int32,
) -> Int32 raise JlsError {
  guard component >= 0 &&
    component < self.components &&
    value >= 0 &&
    value < 1 << self.bits else {
    raise Invalid(0, "histogram bin is outside range")
  }
  self.bins[component][value]
}

///|
pub fn SampleHistogram::nonzero_bins(
  self : SampleHistogram,
  component : Int32,
  maximum_bins~ : Int32 = 65536,
) -> Array[(Int32, Int32)] raise JlsError {
  guard component >= 0 && component < self.components && maximum_bins >= 0 else {
    raise Invalid(0, "invalid component or bin budget")
  }
  let result : Array[(Int32, Int32)] = []
  for value in 0..<(1 << self.bits) {
    let count = self.bins[component][value]
    if count > 0 {
      guard result.length() < maximum_bins else {
        raise Limit(0, "nonzero histogram bin budget exceeded")
      }
      result.push((value, count))
    }
  }
  result
}

///|
/// Nearest-rank quantile with floor(p*(n-1)); endpoints select actual extrema.
pub fn SampleHistogram::quantile(
  self : SampleHistogram,
  component : Int32,
  probability : Double,
) -> Int32 raise JlsError {
  guard component >= 0 &&
    component < self.components &&
    probability >= 0.0 &&
    probability <= 1.0 else {
    raise Invalid(0, "invalid quantile component or probability")
  }
  let samples = self.total / self.components
  guard samples > 0 else { raise Invalid(0, "empty histogram has no quantile") }
  let rank = (probability * (samples - 1).to_double()).floor().to_int()
  let mut cumulative = 0
  for value in 0..<(1 << self.bits) {
    cumulative += self.bins[component][value]
    if cumulative > rank {
      return value
    }
  }
  raise Invalid(0, "inconsistent histogram counters")
}

///|
pub fn SampleHistogram::summary(
  self : SampleHistogram,
  component : Int32,
) -> SampleSummary raise JlsError {
  guard component >= 0 && component < self.components else {
    raise Invalid(0, "histogram component outside range")
  }
  let samples = self.total / self.components
  guard samples > 0 else { raise Invalid(0, "empty histogram has no summary") }
  let mut minimum = (1 << self.bits) - 1
  let mut maximum = 0
  let mut distinct = 0
  let mut most_frequent = 0
  let mut largest_bin = 0
  let mut mean = 0.0
  let mut variance = 0.0
  let mut processed = 0
  let mut entropy = 0.0
  for value in 0..<(1 << self.bits) {
    let count = self.bins[component][value]
    if count == 0 {
      continue
    }
    minimum = minimum.min(value)
    maximum = maximum.max(value)
    distinct += 1
    if count > largest_bin {
      largest_bin = count
      most_frequent = value
    }
    let probability = count.to_double() / samples.to_double()
    entropy -= probability * @math.log2(probability)
    let delta = value.to_double() - mean
    let next = processed + count
    variance += delta *
      delta *
      processed.to_double() *
      count.to_double() /
      next.to_double()
    mean += delta * count.to_double() / next.to_double()
    processed = next
  }
  {
    samples,
    minimum,
    maximum,
    distinct,
    most_frequent,
    mean,
    variance: variance / samples.to_double(),
    entropy_bits: entropy,
  }
}

///|
pub fn SampleHistogram::reset(self : SampleHistogram) -> Unit {
  for component in 0..<self.components {
    self.bins[component].fill(0)
  }
  self.total = 0
}

///|
pub fn ErrorMetrics::psnr(
  self : ErrorMetrics,
  maximum : Int32,
) -> Double? raise JlsError {
  guard maximum >= 1 && maximum <= 65535 && self.mean_squared_error >= 0.0 else {
    raise Invalid(0, "invalid PSNR range or error")
  }
  if self.mean_squared_error == 0.0 {
    None
  } else {
    Some(
      10.0 *
      @math.log10(
        maximum.to_double() * maximum.to_double() / self.mean_squared_error,
      ),
    )
  }
}

///|
pub fn SampleSummary::to_json(self : SampleSummary) -> Json {
  {
    "samples": self.samples,
    "minimum": self.minimum,
    "maximum": self.maximum,
    "distinct": self.distinct,
    "most_frequent": self.most_frequent,
    "mean": self.mean,
    "variance": self.variance,
    "entropy_bits": self.entropy_bits,
  }
}

///|
/// Combines disjoint batches, checking compatibility and capacity before mutation.
/// Self-merge intentionally doubles the observations if the budget permits it.
pub fn SampleHistogram::merge(
  self : SampleHistogram,
  other : SampleHistogram,
) -> Unit raise JlsError {
  guard self.bits == other.bits && self.components == other.components else {
    raise Invalid(0, "histogram formats differ")
  }
  guard other.total <= self.maximum_samples - self.total else {
    raise Limit(0, "merged histogram exceeds sample budget")
  }
  for c in 0..<self.components {
    for value in 0..<self.bins[c].length() {
      self.bins[c][value] += other.bins[c][value]
    }
  }
  self.total += other.total
}

///|
/// Removes a known sub-batch atomically; mismatching bin counts are rejected.
pub fn SampleHistogram::subtract(
  self : SampleHistogram,
  other : SampleHistogram,
) -> Unit raise JlsError {
  guard self.bits == other.bits &&
    self.components == other.components &&
    other.total <= self.total else {
    raise Invalid(0, "histogram is not a compatible sub-batch")
  }
  for c in 0..<self.components {
    for value in 0..<self.bins[c].length() {
      guard other.bins[c][value] <= self.bins[c][value] else {
        raise Invalid(value, "sub-batch bin exceeds accumulated observations")
      }
    }
  }
  let removed = other.total
  for c in 0..<self.components {
    for value in 0..<self.bins[c].length() {
      self.bins[c][value] -= other.bins[c][value]
    }
  }
  self.total -= removed
}
