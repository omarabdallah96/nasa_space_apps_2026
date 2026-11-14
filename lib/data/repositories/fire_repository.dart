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
}
