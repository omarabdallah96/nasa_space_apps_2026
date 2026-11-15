import 'package:latlong2/latlong.dart';

import '../models/danger_forecast.dart';
import '../models/fire_record.dart';
import '../models/hotspot.dart';
import '../models/region.dart';

/// The single seam between the UI and the data source.
///
/// Screens only talk to this interface. Today it is backed by
/// [MockFireRepository]; later [ApiFireRepository] reads the same JSON
/// shapes from the backend (see docs/api_contract.md).
abstract class FireRepository {
  Future<List<Region>> getRegions();
  Future<FireRecord> getRecord(String regionId);
  Future<List<Hotspot>> getRecentHotspots(String regionId);

  /// Fire danger forecast for the next 7 days at the grid point nearest [point].
  /// Throws when the point is outside every region.
  Future<DangerForecast> getDangerForecast(LatLng point);

  /// Fire danger forecast for the next 7 days over a whole region (for the map).
  Future<RegionDanger> getRegionDanger(String regionId);
}
