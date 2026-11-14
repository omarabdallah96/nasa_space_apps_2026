import 'data/repositories/api_fire_repository.dart';
import 'data/repositories/fire_repository.dart';
import 'data/repositories/mock_fire_repository.dart';

/// Flip to false once the backend serves docs/api_contract.md.
const useMockData = true;
const apiBaseUrl = 'https://example.com/ember-almanac';

/// Used by the app and by the background alert check.
FireRepository createRepository() =>
    useMockData ? MockFireRepository() : ApiFireRepository(baseUrl: apiBaseUrl);
