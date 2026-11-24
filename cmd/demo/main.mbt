///|
fn main {
  try {
    let image : @jls.Image = {
      frame: { width: 32, height: 16, bits_per_sample: 12, components: 1, },
      samples: Array::makei(512, i => (i / 32 * 51 + i % 32 * 37) % 4096),
    }
    let lossless = @jls.encode(image)
    let restored = @jls.decode(lossless[:])
    let near = @jls.encode(image, options={
      ..@jls.EncodeOptions::default(),
      near: 3,
    })
    let approximate = @jls.decode(near[:])
    let mut maximum_error = 0
    for i in 0..<image.samples.length() {
      maximum_error = maximum_error.max(
        (image.samples[i] - approximate.samples[i]).abs(),
      )
    }
    println("12-bit grayscale: 32 x 16 samples")
    println(
      "lossless bytes: \{lossless.length()}, exact pixels: \{restored == image}",
    )
    println(
      "NEAR=3 bytes: \{near.length()}, maximum absolute sample error: \{maximum_error}",
    )
  } catch {
    error => println(error.describe())
  }
}
