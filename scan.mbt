// Adapted from CharLS 2.4.2 scan.h.
// Copyright (c) Team CharLS. SPDX-License-Identifier: BSD-3-Clause.

///|
priv struct ScanContexts {
  traits : CodingTraits
  regular : Array[RegularContext]
  run : Array[RunContext]
}

///|
fn ScanContexts::new(preset : Preset, near : Int32) -> ScanContexts {
  let traits = CodingTraits::new(preset, near)
  {
    traits,
    regular: Array::makei(365, _ => RegularContext::new(traits.range)),
    run: [RunContext::new(0, traits.range), RunContext::new(1, traits.range)],
  }
}

///|
fn ScanContexts::encode_regular(
  self : ScanContexts,
  writer : BitWriter,
  q : Int32,
  original : Int32,
  predicted : Int32,
) -> Int32 raise JlsError {
  let sign = signed_direction(q)
  let context = self.regular[q.abs()]
  let k = context.golomb()
  let prediction = (predicted + sign * context.c)
    .max(0)
    .min(self.traits.preset.maximum)
  let error = self.traits.quantize(sign * (original - prediction))
  let corrected = error ^ context.correction(k | self.traits.near)
  writer.write_mapped(
    map_error(corrected),
    k,
    self.traits.limit,
    self.traits.qbpp,
  )
  context.update(error, self.traits.near, self.traits.preset.reset)
  self.traits.reconstruct(prediction, sign * error)
}

///|
fn ScanContexts::decode_regular(
  self : ScanContexts,
  reader : BitsReader,
  q : Int32,
  predicted : Int32,
) -> Int32 raise JlsError {
  let sign = signed_direction(q)
  let context = self.regular[q.abs()]
  let k = context.golomb()
  let prediction = (predicted + sign * context.c)
    .max(0)
    .min(self.traits.preset.maximum)
  let mapped = reader.read_mapped(k, self.traits.limit, self.traits.qbpp)
  let basic = unmap_error(mapped)
  guard basic.abs() <= 65535 else {
    raise Invalid(0, "regular mapped error exceeds sample domain")
  }
  let error = if k == 0 {
    basic ^ context.correction(self.traits.near)
  } else {
    basic
  }
  context.update(error, self.traits.near, self.traits.preset.reset)
  self.traits.reconstruct(prediction, sign * error)
}

///|
fn ScanContexts::encode_interruption(
  self : ScanContexts,
  writer : BitWriter,
  original : Int32,
  ra : Int32,
  rb : Int32,
  run_index : Int32,
  joint : Bool,
) -> Int32 raise JlsError {
  let kind = if !joint && (ra - rb).abs() <= self.traits.near { 1 } else { 0 }
  let context = self.run[kind]
  let prediction = if kind == 1 { ra } else { rb }
  let sign = if kind == 1 { 1 } else { signed_direction(rb - ra) }
  let error = self.traits.quantize(sign * (original - prediction))
  let k = context.golomb()
  let mapped = 2 * error.abs() -
    kind -
    (if context.mapping(error, k) { 1 } else { 0 })
  guard mapped >= 0 else {
    raise Invalid(0, "run interruption generated negative mapped value")
  }
  writer.write_mapped(
    mapped,
    k,
    self.traits.limit - run_exponent(run_index) - 1,
    self.traits.qbpp,
  )
  context.update(error, mapped, self.traits.preset.reset)
  self.traits.reconstruct(prediction, sign * error)
}

///|
fn ScanContexts::decode_interruption(
  self : ScanContexts,
  reader : BitsReader,
  ra : Int32,
  rb : Int32,
  run_index : Int32,
  joint : Bool,
) -> Int32 raise JlsError {
  let kind = if !joint && (ra - rb).abs() <= self.traits.near { 1 } else { 0 }
  let context = self.run[kind]
  let k = context.golomb()
  let mapped = reader.read_mapped(
    k,
    self.traits.limit - run_exponent(run_index) - 1,
    self.traits.qbpp,
  )
  let error = context.unmap(mapped, k)
  guard error.abs() <= 65535 else {
    raise Invalid(0, "run interruption error exceeds sample domain")
  }
  context.update(error, mapped, self.traits.preset.reset)
  let prediction = if kind == 1 { ra } else { rb }
  let sign = if kind == 1 { 1 } else { signed_direction(rb - ra) }
  self.traits.reconstruct(prediction, sign * error)
}

///|
fn encode_run_length(
  writer : BitWriter,
  length : Int32,
  remaining : Int32,
  run_index : Int32,
) -> Int32 raise JlsError {
  let mut rest = length
  let mut index = run_index
  while rest >= 1 << run_exponent(index) {
    writer.write_bit(1)
    rest -= 1 << run_exponent(index)
    index = (index + 1).min(31)
  }
  if length == remaining {
    if rest != 0 {
      writer.write_bit(1)
    }
  } else {
    writer.write_bits(rest, run_exponent(index) + 1)
  }
  index
}

///|
fn decode_run_length(
  reader : BitsReader,
  remaining : Int32,
  run_index : Int32,
) -> (Int32, Int32) raise JlsError {
  let mut length = 0
  let mut index = run_index
  while reader.read_bit() != 0 {
    let block = 1 << run_exponent(index)
    let count = block.min(remaining - length)
    length += count
    if count == block {
      index = (index + 1).min(31)
    }
    if length == remaining {
      break
    }
  }
  if length != remaining {
    length += reader.read_bits(run_exponent(index))
  }
  guard length <= remaining else {
    raise Invalid(0, "run length exceeds scan line")
  }
  (length, index)
}

///|
fn validate_scan_components(
  frame : Frame,
  components : Array[Int32],
  interleave : Interleave,
) -> Unit raise JlsError {
  guard components.length() > 0 && components.length() <= frame.components else {
    raise Invalid(0, "invalid scan component count")
  }
  if interleave == None && components.length() != 1 {
    raise Invalid(0, "noninterleaved scans require one component")
  }
  if interleave != None && components.length() < 2 {
    raise Invalid(0, "interleaved scans require multiple components")
  }
  for i in 0..<components.length() {
    guard components[i] >= 0 && components[i] < frame.components else {
      raise Invalid(0, "scan component outside frame")
    }
    for j in 0..<i {
      guard components[j] != components[i] else {
        raise Invalid(0, "duplicate scan component")
      }
    }
  }
}

///|
fn encode_scalar_line(
  state : ScanContexts,
  writer : BitWriter,
  previous : Array[Int32],
  current : Array[Int32],
  width : Int32,
  run_index : Int32,
) -> Int32 raise JlsError {
  let mut index = run_index
  let mut x = 1
  while x <= width {
    let ra = current[x - 1]
    let rb = previous[x]
    let rc = previous[x - 1]
    let rd = previous[x + 1]
    let q = state.traits.context(ra, rb, rc, rd)
    if q != 0 {
      current[x] = state.encode_regular(
        writer,
        q,
        current[x],
        median_prediction(ra, rb, rc),
      )
      x += 1
    } else {
      let mut run = 0
      while x + run <= width &&
            (current[x + run] - ra).abs() <= state.traits.near {
        current[x + run] = ra
        run += 1
      }
      index = encode_run_length(writer, run, width - x + 1, index)
      x += run
      if x <= width {
        current[x] = state.encode_interruption(
          writer,
          current[x],
          ra,
          previous[x],
          index,
          false,
        )
        index = (index - 1).max(0)
        x += 1
      }
    }
  }
  index
}

///|
fn decode_scalar_line(
  state : ScanContexts,
  reader : BitsReader,
  previous : Array[Int32],
  current : Array[Int32],
  width : Int32,
  run_index : Int32,
) -> Int32 raise JlsError {
  let mut index = run_index
  let mut x = 1
  while x <= width {
    let ra = current[x - 1]
    let rb = previous[x]
    let rc = previous[x - 1]
    let rd = previous[x + 1]
    let q = state.traits.context(ra, rb, rc, rd)
    if q != 0 {
      current[x] = state.decode_regular(
        reader,
        q,
        median_prediction(ra, rb, rc),
      )
      x += 1
    } else {
      let (run, next_index) = decode_run_length(reader, width - x + 1, index)
      index = next_index
      for n in 0..<run {
        current[x + n] = ra
      }
      x += run
      if x <= width {
        current[x] = state.decode_interruption(
          reader,
          ra,
          previous[x],
          index,
          false,
        )
        index = (index - 1).max(0)
        x += 1
      }
    }
  }
  index
}

///|
fn encode_joint_line(
  state : ScanContexts,
  writer : BitWriter,
  previous : Array[Array[Int32]],
  current : Array[Array[Int32]],
  width : Int32,
  run_index : Int32,
) -> Int32 raise JlsError {
  let count = current.length()
  let mut index = run_index
  let mut x = 1
  while x <= width {
    let contexts = Array::make(count, 0)
    let mut all_zero = true
    for c in 0..<count {
      contexts[c] = state.traits.context(
        current[c][x - 1],
        previous[c][x],
        previous[c][x - 1],
        previous[c][x + 1],
      )
      if contexts[c] != 0 {
        all_zero = false
      }
    }
    if !all_zero {
      for c in 0..<count {
        current[c][x] = state.encode_regular(
          writer,
          contexts[c],
          current[c][x],
          median_prediction(
            current[c][x - 1],
            previous[c][x],
            previous[c][x - 1],
          ),
        )
      }
      x += 1
    } else {
      let values = Array::makei(count, c => current[c][x - 1])
      let mut run = 0
      while x + run <= width {
        let mut matches = true
        for c in 0..<count {
          if (current[c][x + run] - values[c]).abs() > state.traits.near {
            matches = false
          }
        }
        if !matches {
          break
        }
        for c in 0..<count {
          current[c][x + run] = values[c]
        }
        run += 1
      }
      index = encode_run_length(writer, run, width - x + 1, index)
      x += run
      if x <= width {
        for c in 0..<count {
          current[c][x] = state.encode_interruption(
            writer,
            current[c][x],
            values[c],
            previous[c][x],
            index,
            true,
          )
        }
        index = (index - 1).max(0)
        x += 1
      }
    }
  }
  index
}

///|
fn decode_joint_line(
  state : ScanContexts,
  reader : BitsReader,
  previous : Array[Array[Int32]],
  current : Array[Array[Int32]],
  width : Int32,
  run_index : Int32,
) -> Int32 raise JlsError {
  let count = current.length()
  let mut index = run_index
  let mut x = 1
  while x <= width {
    let contexts = Array::make(count, 0)
    let mut all_zero = true
    for c in 0..<count {
      contexts[c] = state.traits.context(
        current[c][x - 1],
        previous[c][x],
        previous[c][x - 1],
        previous[c][x + 1],
      )
      if contexts[c] != 0 {
        all_zero = false
      }
    }
    if !all_zero {
      for c in 0..<count {
        current[c][x] = state.decode_regular(
          reader,
          contexts[c],
          median_prediction(
            current[c][x - 1],
            previous[c][x],
            previous[c][x - 1],
          ),
        )
      }
      x += 1
    } else {
      let values = Array::makei(count, c => current[c][x - 1])
      let (run, next_index) = decode_run_length(reader, width - x + 1, index)
      index = next_index
      for n in 0..<run {
        for c in 0..<count {
          current[c][x + n] = values[c]
        }
      }
      x += run
      if x <= width {
        for c in 0..<count {
          current[c][x] = state.decode_interruption(
            reader,
            values[c],
            previous[c][x],
            index,
            true,
          )
        }
        index = (index - 1).max(0)
        x += 1
      }
    }
  }
  index
}

///|
fn encode_scan(
  image : Image,
  components : Array[Int32],
  preset : Preset,
  near : Int32,
  interleave : Interleave,
  limits : Limits,
) -> Bytes raise JlsError {
  image.validate(maximum=preset.maximum, limits~)
  encode_scan_rows(
    image.frame,
    components,
    preset,
    near,
    interleave,
    (y, selected) => {
      Array::makei(image.frame.width * selected.length(), i => {
        image.samples[(y * image.frame.width + i / selected.length()) *
        image.frame.components +
        selected[i % selected.length()]]
      })
    },
    limits,
  )
}

///|
fn encode_scan_rows(
  frame : Frame,
  components : Array[Int32],
  preset : Preset,
  near : Int32,
  interleave : Interleave,
  row_at : (Int32, Array[Int32]) -> Array[Int32] raise JlsError,
  limits : Limits,
) -> Bytes raise JlsError {
  ignore(frame.sample_count(limits~))
  validate_scan_components(frame, components, interleave)
  let state = ScanContexts::new(preset, near)
  let writer = BitWriter::new(limits.compressed_bytes)
  let count = components.length()
  let width = frame.width
  let mut previous = Array::makei(count, _ => Array::make(width + 2, 0))
  let mut current = Array::makei(count, _ => Array::make(width + 2, 0))
  let run_indices = Array::make(count, 0)
  for y in 0..<frame.height {
    let row = row_at(y, components.copy())
    guard row.length() == width * count else {
      raise Invalid(y, "row callback returned wrong sample count")
    }
    for c in 0..<count {
      previous[c][width + 1] = previous[c][width]
      current[c][0] = previous[c][1]
      for x in 0..<width {
        let value = row[x * count + c]
        guard value >= 0 && value <= preset.maximum else {
          raise Invalid(y, "row callback sample exceeds MAXVAL")
        }
        current[c][x + 1] = value
      }
    }
    if interleave == Sample {
      run_indices[0] = encode_joint_line(
        state,
        writer,
        previous,
        current,
        width,
        run_indices[0],
      )
    } else {
      for c in 0..<count {
        run_indices[c] = encode_scalar_line(
          state,
          writer,
          previous[c],
          current[c],
          width,
          run_indices[c],
        )
      }
    }
    let swap = previous
    previous = current
    current = swap
  }
  writer.finish()
}

///|
fn decode_scan(
  data : BytesView,
  start : Int32,
  end : Int32,
  frame : Frame,
  components : Array[Int32],
  preset : Preset,
  near : Int32,
  interleave : Interleave,
  output : Array[Int32],
  limits : Limits,
) -> Unit raise JlsError {
  guard output.length() == frame.sample_count(limits~) else {
    raise Invalid(0, "scan destination size disagrees with frame")
  }
  decode_scan_rows(
    data,
    start,
    end,
    frame,
    components,
    preset,
    near,
    interleave,
    (y, selected, row) => {
      for x in 0..<frame.width {
        for c in 0..<selected.length() {
          output[(y * frame.width + x) * frame.components + selected[c]] = row[x *
            selected.length() +
            c]
        }
      }
    },
    limits,
  )
}

///|
fn decode_scan_rows(
  data : BytesView,
  start : Int32,
  end : Int32,
  frame : Frame,
  components : Array[Int32],
  preset : Preset,
  near : Int32,
  interleave : Interleave,
  emit : (Int32, Array[Int32], Array[Int32]) -> Unit raise JlsError,
  limits : Limits,
) -> Unit raise JlsError {
  ignore(frame.sample_count(limits~))
  validate_scan_components(frame, components, interleave)
  let state = ScanContexts::new(preset, near)
  let reader = BitsReader::new(data, start, end)
  let count = components.length()
  let width = frame.width
  let mut previous = Array::makei(count, _ => Array::make(width + 2, 0))
  let mut current = Array::makei(count, _ => Array::make(width + 2, 0))
  let run_indices = Array::make(count, 0)
  for y in 0..<frame.height {
    for c in 0..<count {
      previous[c][width + 1] = previous[c][width]
      current[c][0] = previous[c][1]
    }
    if interleave == Sample {
      run_indices[0] = decode_joint_line(
        state,
        reader,
        previous,
        current,
        width,
        run_indices[0],
      )
    } else {
      for c in 0..<count {
        run_indices[c] = decode_scalar_line(
          state,
          reader,
          previous[c],
          current[c],
          width,
          run_indices[c],
        )
      }
    }
    let row = Array::makei(width * count, i => current[i % count][i / count + 1])
    emit(y, components.copy(), row)
    let swap = previous
    previous = current
    current = swap
  }
  reader.finish()
}
