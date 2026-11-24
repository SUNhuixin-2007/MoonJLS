///|
pub fn ScanInfo::to_json(self : ScanInfo) -> Json {
  {
    "components": Json::array(
      self.components.map(c => Json::number(c.to_double())),
    ),
    "near": self.near,
    "interleave": self.interleave.code(),
    "preset": self.preset.to_json(),
    "entropy_offset": self.entropy_offset,
    "entropy_end": self.entropy_end,
    "restart_interval": self.restart_interval,
  }
}

///|
pub fn SpiffHeader::to_json(self : SpiffHeader) -> Json {
  {
    "frame": self.frame.to_json(),
    "color_space": self.color_space,
    "resolution_units": self.resolution_units,
    "vertical_resolution": self.vertical_resolution.to_string(),
    "horizontal_resolution": self.horizontal_resolution.to_string(),
  }
}

///|
pub fn Info::to_json(
  self : Info,
  include_metadata~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> Json raise JlsError {
  let spiff : Json = match self.spiff_header(limits~) {
    None => Json::null()
    Some(header) => header.to_json()
  }
  {
    "format": "moonjls.info.v1",
    "frame": self.frame.to_json(),
    "consumed": self.consumed,
    "scans": Json::array(self.scans.map(scan => scan.to_json())),
    "transform": self.color_transform().code(),
    "spiff": spiff,
    "metadata": Json::array(
      self.metadata.map(segment => {
        let base : Map[String, Json] = {
          "marker": Json::number(segment.marker.to_double()),
          "offset": Json::number(segment.offset.to_double()),
          "bytes": Json::number(segment.data.length().to_double()),
        }
        if include_metadata {
          base["hex"] = Json::string(hex_encode(segment.data[:]))
        }
        Json::object(base)
      }),
    ),
  }
}

///|
pub fn RatePoint::to_json(self : RatePoint) -> Json {
  {
    "near": self.near,
    "interleave": self.interleave.code(),
    "bytes": self.compressed_bytes,
    "maximum_error": self.maximum_error,
    "mean_squared_error": self.mean_squared_error,
  }
}
