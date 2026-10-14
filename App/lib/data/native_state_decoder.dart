import '../domain/entities/native_state.dart';
import '../domain/repositories/native_repository.dart';

class NativeStateDecoder {
  static const preferenceKeys = {
    'autoEnabled',
    'typoEnabled',
    'yoEnabled',
    'singleShiftEnabled',
    'optionEnabled',
    'splitShiftEnabled',
    'plainPasteEnabled',
    'soundEnabled',
  };
  static Never invalid() =>
      throw const NativeFailure('invalidArgument', retryable: false);
  static Map<String, Object?> map(Object? value) {
    if (value is! Map || value.keys.any((k) => k is! String)) invalid();
    return Map<String, Object?>.from(value);
  }

  static String string(Object? v, {int limit = 1024}) {
    if (v is! String || v.length > limit) invalid();
    return v;
  }

  static int integer(Object? v) {
    if (v is! int || v < 0 || v > 0x7fffffffffffffff) invalid();
    return v;
  }

  static bool boolean(Object? v) {
    if (v is! bool) invalid();
    return v;
  }

  static String enumeration(Object? v, Set<String> values) {
    final s = string(v);
    if (!values.contains(s)) invalid();
    return s;
  }

  static void keys(Map<String, Object?> m, Set<String> expected) {
    if (m.length != expected.length || !m.keys.toSet().containsAll(expected)) {
      invalid();
    }
  }

  static Map<String, bool> flags(Object? v, Set<String> expected) {
    final m = map(v);
    keys(m, expected);
    return m.map((k, v) => MapEntry(k, boolean(v)));
  }

  static void date(Object? v) {
    if (v != null &&
        (v is! String || DateTime.tryParse(v) == null || !v.endsWith('Z'))) {
      invalid();
    }
  }

  static NativeState decode(Object? value) {
    final m = map(value);
    if (m['schema'] is! int || m['schema'] != 1) {
      throw const NativeFailure('unsupportedSchema', retryable: false);
    }
    keys(m, {
      'schema',
      'sessionID',
      'revision',
      'preferences',
      'capabilities',
      'status',
      'words',
      'apps',
      'model',
      'license',
      'statistics',
      'appearance',
      'login',
    });
    final session = string(m['sessionID']);
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(session)) {
      invalid();
    }
    List<Map<String, Object?>> rules(Object? value, bool words) {
      if (value is! List || value.length > 10000) invalid();
      final ids = <String>{};
      return value.map((v) {
        final r = map(v);
        keys(
          r,
          words
              ? {'id', 'normalized', 'original', 'createdAt', 'legacy'}
              : {'bundleID', 'displayName', 'mode'},
        );
        final id = string(r[words ? 'id' : 'bundleID']);
        if (id.isEmpty || !ids.add(id)) invalid();
        if (words) {
          string(r['normalized']);
          string(r['original']);
          if (r['createdAt'] == null) invalid();
          date(r['createdAt']);
          boolean(r['legacy']);
        } else {
          string(r['displayName']);
          enumeration(r['mode'], {'allow', 'deny'});
        }
        return r;
      }).toList();
    }

    final model = map(m['model']);
    keys(model, {'version', 'lastChecked', 'state'});
    if (!RegExp(r'^\d+$').hasMatch(string(model['version']))) invalid();
    date(model['lastChecked']);
    enumeration(model['state'], {'idle', 'checking', 'current', 'failed'});
    final license = map(m['license']);
    keys(license, {'state', 'expiresAt'});
    date(license['expiresAt']);
    enumeration(license['state'], {
      'checking',
      'trial',
      'active',
      'grace',
      'pending',
      'expired',
      'revoked',
      'unavailable',
    });
    final appearance = map(m['appearance']);
    keys(appearance, {'colorIndex', 'hasCustomSound', 'hasHeaderImage'});
    if (integer(appearance['colorIndex']) > 24) invalid();
    boolean(appearance['hasCustomSound']);
    boolean(appearance['hasHeaderImage']);
    final login = map(m['login']);
    keys(login, {'enabled', 'status'});
    boolean(login['enabled']);
    enumeration(login['status'], {
      'enabled',
      'disabled',
      'requiresApproval',
      'unavailable',
    });
    final statistics = map(m['statistics']);
    if (statistics.length > 64) invalid();
    return NativeState(
      sessionID: session,
      revision: integer(m['revision']),
      preferences: flags(m['preferences'], preferenceKeys),
      capabilities: flags(m['capabilities'], {
        'listen',
        'post',
        'axTrusted',
        'secureInput',
      }),
      status: enumeration(m['status'], {
        'active',
        'off',
        'permissionRequired',
        'secureInput',
        'licensingBlocked',
        'updateAvailable',
      }),
      words: rules(m['words'], true),
      apps: rules(m['apps'], false),
      model: model,
      license: license,
      statistics: statistics.map((k, v) => MapEntry(k, integer(v))),
      appearance: appearance,
      login: login,
    );
  }

  static Map<String, Object?> encode(NativeState s) => {
    'schema': 1,
    'sessionID': s.sessionID,
    'revision': s.revision,
    'preferences': s.preferences,
    'capabilities': s.capabilities,
    'status': s.status,
    'words': s.words,
    'apps': s.apps,
    'model': s.model,
    'license': s.license,
    'statistics': s.statistics,
    'appearance': s.appearance,
    'login': s.login,
  };
}
