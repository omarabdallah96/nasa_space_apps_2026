import 'data/repositories/api_fire_repository.dart';
import 'data/repositories/fire_repository.dart';
import 'data/repositories/mock_fire_repository.dart';
import 'services/auth_api.dart';
import 'services/broadcast_api.dart';
import 'services/report_api.dart';

/// Live data from the Firesight backend. Build with
/// `--dart-define=USE_MOCK=true` to use the bundled demo data instead, or
/// `--dart-define=API_BASE_URL=...` to point at another server.
const useMockData = bool.fromEnvironment('USE_MOCK');
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://cedx.coding-now.online/api/v1',
);

/// Used by the app and by the background alert check.
FireRepository createRepository() =>
    useMockData ? MockFireRepository() : ApiFireRepository(baseUrl: apiBaseUrl);

/// Shares field reports with other phones; demo mode keeps them on the phone.
ReportApi? createReportApi() => useMockData ? null : ReportApi(baseUrl: apiBaseUrl);

/// Optional sign-in; demo mode has no accounts, so everyone is a guest.
AuthApi? createAuthApi() => useMockData ? null : AuthApi(baseUrl: apiBaseUrl);

/// Zone alerts sent from the admin page; demo mode has none.
BroadcastApi? createBroadcastApi() => useMockData ? null : BroadcastApi(baseUrl: apiBaseUrl);
