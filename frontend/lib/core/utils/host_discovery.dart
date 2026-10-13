import 'dart:io';

import '../constants/app_constants.dart';

/// LAN host auto-discovery.
///
/// When the app runs on a device (Android/iOS/desktop), `defaultHost` is a
/// hardcoded PC IP that breaks whenever DHCP assigns a new address. This
/// service finds the backend automatically instead:
///
/// 1. Take the device's own LAN subnet (e.g. 10.20.2.x) from its interfaces.
/// 2. Probe a small set of candidate hosts (gateway address first — the PC is
///    usually the same box or on the same subnet) for a `/health` 200 response
///    on the API port.
/// 3. If that fails, scan the ENTIRE /24 subnet in parallel — this finds the
///    PC even after DHCP hands out a brand-new address.
/// 4. Fall back to `defaultHost` if nothing is found.
///
/// The result is cached for the app's lifetime; call [resolve] once at startup.
class HostDiscovery {
  HostDiscovery._();
  static String? _resolvedHost;

  /// The last successfully discovered host, or null before discovery ran.
  static String? get resolvedHost => _resolvedHost;

  /// Returns a host in `ip:port` form for the API backend.
  ///
  /// [timeoutPerCandidate] bounds how long we wait on each probe.
  static Future<String> resolve({
    Duration timeoutPerCandidate = const Duration(milliseconds: 800),
  }) async {
    if (_resolvedHost != null) return _resolvedHost!;

    // 1. Collect the /24 subnets this device belongs to (RFC 1918 only),
    //    remembering the device's own address(es) too — when the app runs on
    //    the same PC as the backend, that address IS the backend address.
    final subnets = <String>{};
    final ownIps = <String>{};
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          final ip = addr.address;
          final parts = ip.split('.');
          if (parts.length != 4) continue;
          final first = int.parse(parts[0]);
          final isPrivate = (first == 10) ||
              (first == 192 && parts[1] == '168') ||
              (first == 172 && int.parse(parts[1]) >= 16 && int.parse(parts[1]) <= 31);
          if (!isPrivate) continue;
          ownIps.add(ip);
          subnets.add('${parts[0]}.${parts[1]}.${parts[2]}.');
        }
      }
    } catch (_) {
      // Interface listing can fail on some platforms; fall back below.
    }

    // 2. Probe candidates: gateway-ish addresses (.1/.2) and, on Android
    //    emulators, the special 10.0.2.2 host loopback.
    final candidates = <String>['10.0.2.2'];
    for (final s in subnets) {
      candidates..add('${s}1')..add('${s}2');
      // The device's own address (app and backend on the same machine).
      candidates.addAll(ownIps);
    }
    // The hardcoded default is also a candidate.
    candidates.add(AppConstants.defaultHost.split(':').first);

    for (final ip in candidates.toSet()) {
      if (await _probe('$ip:${AppConstants.apiPort}', timeoutPerCandidate)) {
        _resolvedHost = '$ip:${AppConstants.apiPort}';
        return _resolvedHost!;
      }
    }

    // 3. Full subnet sweep in parallel — survives any DHCP reassignment.
    for (final s in subnets) {
      final found = await _sweepSubnet(s, timeoutPerCandidate);
      if (found != null) {
        _resolvedHost = '$found:${AppConstants.apiPort}';
        return _resolvedHost!;
      }
    }

    _resolvedHost = AppConstants.defaultHost;
    return _resolvedHost!;
  }

  /// Probes every address 1..254 in the /24 [subnet] in parallel and returns
  /// the first IP whose `/health` answers 200, or null.
  static Future<String?> _sweepSubnet(String subnet, Duration timeout) async {
    final futures = <Future<String?>>[];
    for (var i = 1; i <= 254; i++) {
      final ip = '$subnet$i';
      futures.add(_probe(ip, timeout).then((ok) => ok ? ip : null));
    }
    try {
      final results = await futures.wait;
      return results.firstWhere((ip) => ip != null, orElse: () => null);
    } catch (_) {
      return null;
    }
  }

  /// True if `http://<host>/health` responds 200.
  static Future<bool> _probe(String host, Duration timeout) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = timeout;
      final request =
          await client.getUrl(Uri.parse('http://$host/health')).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final ok = response.statusCode == 200;
      await response.drain<void>();
      client.close(force: true);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Forget the cached host (e.g. after a network change / manual clear).
  static void reset() => _resolvedHost = null;
}
