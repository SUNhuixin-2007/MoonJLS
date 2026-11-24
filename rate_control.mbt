///|
pub(all) struct RatePoint {
  near : Int32
  interleave : Interleave
  compressed_bytes : Int32
  maximum_error : Int32
  mean_squared_error : Double
} derive(Eq, @debug.Debug)

///|
pub(all) struct EncodingChoice {
  point : RatePoint
  codestream : Bytes
  attempts : Int32
} derive(Eq, @debug.Debug)

///|
fn validate_rate_candidates(
  image : Image,
  near_levels : Array[Int32],
  modes : Array[Interleave],
  maximum_attempts : Int32,
  work_sample_budget : UInt64,
  limits : Limits,
) -> Unit raise JlsError {
  image.validate(limits~)
  guard maximum_attempts >= 1 && !near_levels.is_empty() && !modes.is_empty() else {
    raise Invalid(0, "empty rate search or invalid attempt bound")
  }
  guard near_levels.length() <= maximum_attempts / modes.length() else {
    raise Limit(0, "encoding candidate count exceeds attempt budget")
  }
  let attempts = near_levels.length() * modes.length()
  guard image.samples.length().to_uint64() <=
    work_sample_budget / attempts.to_uint64() else {
    raise Limit(0, "rate search exceeds sample-work budget")
  }
  let maximum = (1 << image.frame.bits_per_sample) - 1
  for i in 0..<near_levels.length() {
    ignore(Preset::defaults(maximum, near_levels[i]))
    for j in 0..<i {
      guard near_levels[i] != near_levels[j] else {
        raise Invalid(0, "duplicate NEAR candidate")
      }
    }
  }
  for i in 0..<modes.length() {
    guard image.frame.components > 1 || modes[i] == None else {
      raise Invalid(0, "grayscale candidate must be noninterleaved")
    }
    for j in 0..<i {
      guard modes[i] != modes[j] else {
        raise Invalid(0, "duplicate interleave candidate")
      }
    }
  }
}

///|
fn measure_rate(
  image : Image,
  near : Int32,
  mode : Interleave,
  limits : Limits,
) -> (RatePoint, Bytes) raise JlsError {
  let options = { ..EncodeOptions::default(), near, interleave: mode, }
  let bytes = encode(image, options~, limits~)
  let decoded = decode(bytes[:], limits~)
  let metrics = verify_near(image, decoded, near, limits~)
  (
    {
      near,
      interleave: mode,
      compressed_bytes: bytes.length(),
      maximum_error: metrics.maximum_error,
      mean_squared_error: metrics.mean_squared_error,
    },
    bytes,
  )
}

///|
/// Measures real encodings rather than estimating an unspecified JPEG quality
/// scale. Candidate count and total processed samples have separate budgets.
pub fn rate_curve(
  image : Image,
  near_levels : Array[Int32],
  modes : Array[Interleave],
  maximum_attempts~ : Int32 = 32,
  work_sample_budget~ : UInt64 = 268435456UL,
  limits~ : Limits = Limits::default(),
) -> Array[RatePoint] raise JlsError {
  validate_rate_candidates(
    image, near_levels, modes, maximum_attempts, work_sample_budget, limits,
  )
  let result : Array[RatePoint] = []
  for near in near_levels {
    for mode in modes {
      let (point, _) = measure_rate(image, near, mode, limits)
      result.push(point)
    }
  }
  result
}

///|
fn rate_better(a : RatePoint, b : RatePoint) -> Bool {
  if a.maximum_error != b.maximum_error {
    a.maximum_error < b.maximum_error
  } else if a.mean_squared_error != b.mean_squared_error {
    a.mean_squared_error < b.mean_squared_error
  } else if a.compressed_bytes != b.compressed_bytes {
    a.compressed_bytes < b.compressed_bytes
  } else if a.near != b.near {
    a.near < b.near
  } else {
    a.interleave.code() < b.interleave.code()
  }
}

///|
/// Finds the best measured candidate fitting a byte budget, prioritizing maximum
/// error, then MSE, then bytes. None means no tested candidate fit; it does not
/// assert that the image cannot be encoded under that budget by any algorithm.
pub fn encode_to_budget(
  image : Image,
  maximum_bytes : Int32,
  near_levels : Array[Int32],
  modes : Array[Interleave],
  maximum_attempts~ : Int32 = 32,
  work_sample_budget~ : UInt64 = 268435456UL,
  limits~ : Limits = Limits::default(),
) -> EncodingChoice? raise JlsError {
  guard maximum_bytes >= 0 && maximum_bytes <= limits.compressed_bytes else {
    raise Invalid(0, "invalid compressed byte target")
  }
  validate_rate_candidates(
    image, near_levels, modes, maximum_attempts, work_sample_budget, limits,
  )
  let mut best : EncodingChoice? = None
  let mut attempts = 0
  for near in near_levels {
    for mode in modes {
      let (point, bytes) = measure_rate(image, near, mode, limits)
      attempts += 1
      if bytes.length() <= maximum_bytes {
        let better = match best {
          None => true
          Some(old) => rate_better(point, old.point)
        }
        if better {
          best = Some({ point, codestream: bytes, attempts: 0, })
        }
      }
    }
  }
  match best {
    None => None
    Some(choice) => Some({ ..choice, attempts, })
  }
}
