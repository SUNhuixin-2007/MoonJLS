///|
test "single bit stuffing follows FF and preserves seven following data bits" {
  let writer = BitWriter::new(100)
  writer.write_bits(255, 8)
  writer.write_bits(127, 7)
  writer.write_bits(0, 3)
  let bytes = writer.finish()
  assert_eq(hex_encode(bytes[:]), "ff7f00")
  let reader = BitsReader::new(bytes[:], 0, bytes.length())
  assert_eq(reader.read_bits(8), 255)
  assert_eq(reader.read_bits(7), 127)
  assert_eq(reader.read_bits(3), 0)
  reader.finish()
  let writer2 = BitWriter::new(100)
  writer2.write_bits(255, 8)
  assert_eq(writer2.finish(), b"\xff\x00")
}

///|
test "limited Golomb ordinary and escape values over supported precision" {
  for qbpp in [2, 8, 12, 16] {
    let limit = 2 * (qbpp + qbpp.max(8))
    for k in [0, 1, 3, 6] {
      let values = [0, 1, 2, 3, (1 << qbpp) - 1]
      let writer = BitWriter::new(1000)
      for value in values {
        writer.write_mapped(value, k, limit, qbpp)
      }
      let bytes = writer.finish()
      let reader = BitsReader::new(bytes[:], 0, bytes.length())
      for value in values {
        assert_eq(reader.read_mapped(k, limit, qbpp), value)
      }
      reader.finish()
    }
  }
}

///|
test "malformed entropy refuses marker bits, missing unary and extra padding" {
  for bytes in [b"\x00", b"\xff\x80"] {
    let reader = BitsReader::new(bytes[:], 0, bytes.length())
    assert_true(
      try {
        ignore(reader.read_unary(20))
        false
      } catch {
        _ => true
      },
    )
  }
  let reader = BitsReader::new(b"\x81"[:], 0, 1)
  ignore(reader.read_bit())
  assert_true(
    try {
      reader.finish()
      false
    } catch {
      _ => true
    },
  )
  let writer = BitWriter::new(1)
  assert_true(
    try {
      writer.write_bits(255, 8)
      ignore(writer.finish())
      false
    } catch {
      _ => true
    },
  )
}
