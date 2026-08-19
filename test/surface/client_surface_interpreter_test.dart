import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

const _interpreter = ClientSurfaceInterpreter();

ClientSurfaceInterpretation _interpret(Map<String, Object?> manifest) =>
    _interpreter.interpret(KumweJsonObject.from(manifest));

Map<String, Object?> _screen({
  String id = 'acme.orders.admin.screen.orders',
  String kind = 'collection',
  Map<String, Object?>? overrides,
}) {
  return {
    'id': id,
    'kind': kind,
    'label': {'default': 'Orders'},
    'order': 10,
    'required_capabilities': <Object?>['acme.orders.read'],
    'required_operations': <Object?>['browse', 'read'],
    'definition': 'acme.order',
    'field_presentations': {
      'order_number': {'widget': 'text', 'emphasis': 'primary'},
    },
    ...?overrides,
  };
}

Map<String, Object?> _navigation({
  String id = 'acme.orders.admin.nav.orders',
  String screen = 'acme.orders.admin.screen.orders',
  Map<String, Object?>? overrides,
}) {
  return {
    'id': id,
    'label': {'default': 'Orders'},
    'screen': screen,
    'order': 10,
    'icon': 'records',
    'required_capabilities': <Object?>['acme.orders.read'],
    ...?overrides,
  };
}

Map<String, Object?> _surface({
  String id = 'acme.orders.admin.workspace',
  List<Object?>? screens,
  List<Object?>? navigation,
  Map<String, Object?>? overrides,
}) {
  return {
    'id': id,
    'audience': 'administrator',
    'kind': 'workspace',
    'label': {'default': 'Orders'},
    'order': 10,
    'required_capabilities': <Object?>['acme.orders.read'],
    'unsupported_behavior': 'hide',
    'navigation': navigation ?? <Object?>[_navigation()],
    'screens': screens ?? <Object?>[_screen()],
    ...?overrides,
  };
}

Map<String, Object?> _manifest({
  List<Object?>? surfaces,
  Map<String, Object?>? overrides,
}) {
  return {
    r'$schema': ClientSurfaceInterpreter.schemaId,
    'schema_version': 1,
    'manifest_id': 'acme.orders.client',
    'owner': {
      'extension': 'acme/orders',
      'version': '1.0.0',
      'checksum': 'sha256:${'1' * 64}',
    },
    'runtime': {'generation': 42, 'checksum': 'sha256:${'2' * 64}'},
    'required_contracts': <Object?>[
      {'id': 'kumwe.client-surface', 'version_range': '^1.0.0'},
    ],
    'surfaces': surfaces ?? <Object?>[_surface()],
    ...?overrides,
  };
}

void main() {
  group('shipped proposal examples', () {
    test('every example manifest interprets with no loss', () {
      final examples = Directory('contracts/examples')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.client-surface.json'))
          .toList();
      expect(examples, isNotEmpty);

      for (final file in examples) {
        final result = _interpreter.interpret(
          KumweJsonObject.parse(file.readAsStringSync()),
        );
        expect(result.rejections, isEmpty, reason: file.path);
        expect(result.notices, isEmpty, reason: file.path);
        expect(result.isUsable, isTrue, reason: file.path);
        expect(result.manifest!.surfaces, isNotEmpty, reason: file.path);
      }
    });

    test('interprets the asset inspection surfaces exactly', () {
      final result = _interpreter.interpret(
        KumweJsonObject.parse(
          File(
            'contracts/examples/asset-inspection.client-surface.json',
          ).readAsStringSync(),
        ),
      );
      final manifest = result.manifest!;
      expect(manifest.surfaces, hasLength(2));
      expect(
        manifest.surfacesFor(ClientSurfaceAudience.administrator),
        hasLength(1),
      );
      expect(manifest.surfacesFor(ClientSurfaceAudience.portal), hasLength(1));

      final admin = manifest
          .surfacesFor(ClientSurfaceAudience.administrator)
          .single;
      expect(admin.kind, ClientSurfaceKind.workspace);
      expect(admin.screens, hasLength(2));
      expect(admin.navigation, hasLength(2));
      for (final item in admin.navigation) {
        expect(admin.screen(item.screen), isNotNull);
      }

      final report = admin.screens.firstWhere(
        (screen) => screen.kind == ClientScreenKind.report,
      );
      expect(report.report, isNotNull);
      expect(report.definition, isNull);
      expect(report.fieldPresentations, isEmpty);

      final portalDocument = manifest
          .surfacesFor(ClientSurfaceAudience.portal)
          .single
          .screens
          .single;
      expect(portalDocument.kind, ClientScreenKind.document);
      expect(portalDocument.definition, isNotNull);
      expect(portalDocument.view, isNotNull);
    });
  });

  group('envelope', () {
    test('admits a well-formed manifest', () {
      final result = _interpret(_manifest());
      expect(result.rejections, isEmpty);
      expect(result.isUsable, isTrue);
      expect(result.manifest!.owner.extension, 'acme/orders');
      expect(result.manifest!.runtime.generation, 42);
      expect(result.manifest!.requiredContracts, hasLength(1));
    });

    test('refuses an unreadable schema identity or version outright', () {
      for (final override in [
        {r'$schema': 'urn:kumwe:proposal:schema:client-surface-manifest:9.9.9'},
        {'schema_version': 2},
      ]) {
        final result = _interpret(_manifest(overrides: override));
        expect(result.manifest, isNull, reason: '$override');
        expect(result.isUsable, isFalse);
        expect(
          result.rejections.single.reason,
          ClientSurfaceRejectionReason.unsupportedSchema,
        );
      }
    });

    test('refuses a malformed envelope naming the exact defect', () {
      // Each case names the path it must fail on, so a case cannot pass by
      // tripping some unrelated violation.
      final cases = <({String path, Map<String, Object?> override})>[
        (path: r'$.manifest_id', override: {'manifest_id': 'not.namespaced'}),
        (
          path: r'$.owner.version',
          override: {
            'owner': <String, Object?>{
              'extension': 'acme/orders',
              'checksum': 'sha256:${'1' * 64}',
            },
          },
        ),
        (
          path: r'$.owner.extension',
          override: {
            'owner': {
              'extension': 'Acme/Orders',
              'version': '1.0.0',
              'checksum': 'sha256:${'1' * 64}',
            },
          },
        ),
        (
          path: r'$.runtime.generation',
          override: {
            'runtime': {'generation': -1, 'checksum': 'sha256:${'2' * 64}'},
          },
        ),
        (
          path: r'$.runtime.checksum',
          override: {
            'runtime': {'generation': 1, 'checksum': 'md5:abc'},
          },
        ),
        (
          path: r'$.required_contracts',
          override: {'required_contracts': <Object?>[]},
        ),
        (path: r'$.surfaces', override: {'surfaces': <Object?>[]}),
        (path: r'$.unexpected_member', override: {'unexpected_member': true}),
      ];

      for (final testCase in cases) {
        final result = _interpret(_manifest(overrides: testCase.override));
        final reason = testCase.path;
        expect(result.manifest, isNull, reason: reason);
        expect(result.rejections, hasLength(1), reason: reason);
        final rejection = result.rejections.single;
        expect(rejection.surfaceId, isNull, reason: reason);
        expect(rejection.path, testCase.path, reason: reason);
        expect(
          rejection.reason,
          ClientSurfaceRejectionReason.structuralViolation,
          reason: reason,
        );
      }
    });

    test('refuses duplicate contract requirements', () {
      final result = _interpret(
        _manifest(
          overrides: {
            'required_contracts': <Object?>[
              {'id': 'kumwe.client-surface', 'version_range': '^1.0.0'},
              {'id': 'kumwe.client-surface', 'version_range': '^2.0.0'},
            ],
          },
        ),
      );
      expect(result.manifest, isNull);
      expect(
        result.rejections.single.reason,
        ClientSurfaceRejectionReason.duplicateIdentifier,
      );
    });
  });

  group('unknown vocabulary', () {
    test('fails a surface closed on unknown required vocabulary', () {
      final cases = <String, Object?>{
        'audience': 'kiosk',
        'kind': 'dashboard',
        'unsupported_behavior': 'degrade',
      };
      for (final entry in cases.entries) {
        final result = _interpret(
          _manifest(
            surfaces: <Object?>[
              _surface(overrides: {entry.key: entry.value}),
            ],
          ),
        );
        expect(result.isUsable, isFalse, reason: entry.key);
        expect(
          result.rejections.single.reason,
          ClientSurfaceRejectionReason.unknownRequiredVocabulary,
          reason: entry.key,
        );
      }
    });

    test('fails a surface closed on an unpresentable widget', () {
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              screens: <Object?>[
                _screen(
                  overrides: {
                    'field_presentations': {
                      'order_number': {'widget': 'holographic_projection'},
                    },
                  },
                ),
              ],
            ),
          ],
        ),
      );
      expect(result.isUsable, isFalse);
      expect(
        result.rejections.single.reason,
        ClientSurfaceRejectionReason.unknownRequiredVocabulary,
      );
      expect(result.rejections.single.surfaceId, 'acme.orders.admin.workspace');
    });

    test('fails a surface closed on an unknown required operation', () {
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              screens: <Object?>[
                _screen(
                  overrides: {
                    'required_operations': <Object?>['browse', 'teleport'],
                  },
                ),
              ],
            ),
          ],
        ),
      );
      expect(result.isUsable, isFalse);
      expect(
        result.rejections.single.reason,
        ClientSurfaceRejectionReason.unknownRequiredVocabulary,
      );
    });

    test('omits unknown optional hints with a notice, keeping the surface', () {
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              navigation: <Object?>[
                _navigation(overrides: {'icon': 'spaceship'}),
              ],
              screens: <Object?>[
                _screen(
                  overrides: {
                    'field_presentations': {
                      'order_number': {
                        'widget': 'text',
                        'emphasis': 'shouty',
                        'width': 'quarter',
                      },
                    },
                  },
                ),
              ],
            ),
          ],
        ),
      );

      expect(result.isUsable, isTrue);
      expect(result.rejections, isEmpty);
      expect(result.notices, hasLength(3));
      final surface = result.manifest!.surfaces.single;
      expect(surface.navigation.single.icon, isNull);
      final presentation =
          surface.screens.single.fieldPresentations.values.single;
      expect(presentation.widget, ClientFieldWidget.text);
      expect(presentation.emphasis, isNull);
      expect(presentation.width, isNull);
    });
  });

  group('surface isolation', () {
    test('one refused surface never removes the others', () {
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(),
            _surface(
              id: 'acme.orders.portal.workspace',
              overrides: {'audience': 'kiosk'},
            ),
            _surface(
              id: 'acme.orders.invoices.workspace',
              navigation: <Object?>[
                _navigation(
                  id: 'acme.orders.invoices.nav.list',
                  screen: 'acme.orders.invoices.screen.list',
                ),
              ],
              screens: <Object?>[
                _screen(id: 'acme.orders.invoices.screen.list'),
              ],
            ),
          ],
        ),
      );

      expect(result.manifest!.surfaces, hasLength(2));
      expect(
        result.manifest!.surfaces.map((surface) => surface.id),
        containsAll([
          'acme.orders.admin.workspace',
          'acme.orders.invoices.workspace',
        ]),
      );
      expect(
        result.rejections.single.surfaceId,
        'acme.orders.portal.workspace',
      );
    });

    test('notices from a refused surface are withdrawn with it', () {
      // The notice has to be created before the failure, or the assertion is
      // vacuous. Screens are read before navigation, so both live in
      // navigation: the first item drops an unsupported icon, and the second
      // points at a screen this surface never declares.
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              navigation: <Object?>[
                _navigation(overrides: {'icon': 'spaceship'}),
                _navigation(
                  id: 'acme.orders.admin.nav.missing',
                  screen: 'acme.orders.admin.screen.absent',
                ),
              ],
            ),
          ],
        ),
      );

      expect(result.isUsable, isFalse);
      expect(
        result.rejections.single.reason,
        ClientSurfaceRejectionReason.unresolvedReference,
      );
      expect(
        result.notices,
        isEmpty,
        reason: 'a refused surface must not leave advisory residue',
      );
    });

    test('keeps an admitted surface notice when a later twin is refused', () {
      // The refused duplicate shares the admitted surface's identifier, so
      // withdrawing notices by identifier would silently lose the admitted
      // surface's dropped icon.
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              navigation: <Object?>[
                _navigation(overrides: {'icon': 'spaceship'}),
              ],
            ),
            _surface(),
          ],
        ),
      );

      expect(result.manifest!.surfaces, hasLength(1));
      expect(
        result.rejections.single.reason,
        ClientSurfaceRejectionReason.duplicateIdentifier,
      );
      expect(result.notices, hasLength(1));
      expect(result.notices.single.path, endsWith('.icon'));
      expect(result.manifest!.surfaces.single.navigation.single.icon, isNull);
    });

    test('refuses duplicate surface identifiers', () {
      final result = _interpret(
        _manifest(surfaces: <Object?>[_surface(), _surface()]),
      );
      expect(result.manifest!.surfaces, hasLength(1));
      expect(
        result.rejections.single.reason,
        ClientSurfaceRejectionReason.duplicateIdentifier,
      );
    });
  });

  group('reference integrity', () {
    test('refuses navigation pointing outside its own surface', () {
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              navigation: <Object?>[
                _navigation(screen: 'acme.orders.invoices.screen.list'),
              ],
            ),
            _surface(
              id: 'acme.orders.invoices.workspace',
              navigation: <Object?>[
                _navigation(
                  id: 'acme.orders.invoices.nav.list',
                  screen: 'acme.orders.invoices.screen.list',
                ),
              ],
              screens: <Object?>[
                _screen(id: 'acme.orders.invoices.screen.list'),
              ],
            ),
          ],
        ),
      );

      expect(result.manifest!.surfaces, hasLength(1));
      expect(
        result.rejections.single.reason,
        ClientSurfaceRejectionReason.unresolvedReference,
      );
      expect(result.rejections.single.surfaceId, 'acme.orders.admin.workspace');
    });

    test('refuses identifiers outside the owning extension namespace', () {
      // acme/orders may declare acme.orders.*, never another vendor's space.
      final impersonatingSurface = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(id: 'rival.orders.admin.workspace'),
            _surface(),
          ],
        ),
      );
      expect(impersonatingSurface.manifest!.surfaces, hasLength(1));
      expect(
        impersonatingSurface.manifest!.surfaces.single.id,
        'acme.orders.admin.workspace',
      );
      expect(
        impersonatingSurface.rejections.single.reason,
        ClientSurfaceRejectionReason.ownerNamespaceEscape,
      );

      final impersonatingScreen = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              navigation: <Object?>[
                _navigation(screen: 'rival.orders.admin.screen.orders'),
              ],
              screens: <Object?>[
                _screen(id: 'rival.orders.admin.screen.orders'),
              ],
            ),
          ],
        ),
      );
      expect(
        impersonatingScreen.rejections.single.reason,
        ClientSurfaceRejectionReason.ownerNamespaceEscape,
      );

      final impersonatingManifest = _interpret(
        _manifest(overrides: {'manifest_id': 'rival.orders.client'}),
      );
      expect(impersonatingManifest.manifest, isNull);
      expect(
        impersonatingManifest.rejections.single.reason,
        ClientSurfaceRejectionReason.ownerNamespaceEscape,
      );
    });

    test('refuses duplicate screen and navigation identifiers', () {
      final duplicateScreens = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(screens: <Object?>[_screen(), _screen()]),
          ],
        ),
      );
      expect(
        duplicateScreens.rejections.single.reason,
        ClientSurfaceRejectionReason.duplicateIdentifier,
      );

      final duplicateNavigation = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(navigation: <Object?>[_navigation(), _navigation()]),
          ],
        ),
      );
      expect(
        duplicateNavigation.rejections.single.reason,
        ClientSurfaceRejectionReason.duplicateIdentifier,
      );
    });
  });

  group('screen shape', () {
    test('enforces the required members of every screen kind', () {
      // Each case is an otherwise-valid screen of its kind with exactly one
      // required member removed, named by `omitted`.
      final cases =
          <({String kind, String omitted, Map<String, Object?> screen})>[
            (
              kind: 'collection',
              omitted: 'definition',
              screen: _screen(overrides: {'kind': 'collection'})
                ..remove('definition'),
            ),
            (
              kind: 'record',
              omitted: 'definition',
              screen: _screen(overrides: {'kind': 'record'})
                ..remove('definition'),
            ),
            (
              kind: 'form',
              omitted: 'mode',
              screen: _screen(overrides: {'kind': 'form'}),
            ),
            (
              kind: 'document',
              omitted: 'view',
              screen: _screen(overrides: {'kind': 'document'}),
            ),
            (
              kind: 'report',
              omitted: 'report',
              screen: _screen(overrides: {'kind': 'report'})
                ..remove('definition')
                ..remove('field_presentations'),
            ),
          ];

      for (final testCase in cases) {
        final reason = '${testCase.kind} without ${testCase.omitted}';
        expect(
          testCase.screen.containsKey(testCase.omitted),
          isFalse,
          reason: '$reason: the fixture must actually omit the member',
        );
        final result = _interpret(
          _manifest(
            surfaces: <Object?>[
              _surface(screens: <Object?>[testCase.screen]),
            ],
          ),
        );
        expect(result.isUsable, isFalse, reason: reason);
        final rejection = result.rejections.single;
        expect(
          rejection.reason,
          ClientSurfaceRejectionReason.structuralViolation,
          reason: reason,
        );
        expect(
          rejection.path,
          endsWith('.${testCase.omitted}'),
          reason: '$reason: the rejection must name the missing member',
        );
      }
    });

    test('refuses members a screen kind forbids', () {
      final forbidden = <Map<String, Object?>>[
        {'kind': 'collection', 'mode': 'create'},
        {'kind': 'record', 'view': 'summary'},
        {'kind': 'form', 'mode': 'create', 'report': 'acme.report'},
        {'kind': 'document', 'view': 'lines', 'mode': 'update'},
      ];
      for (final override in forbidden) {
        final result = _interpret(
          _manifest(
            surfaces: <Object?>[
              _surface(screens: <Object?>[_screen(overrides: override)]),
            ],
          ),
        );
        expect(result.isUsable, isFalse, reason: '$override');
        expect(
          result.rejections.single.reason,
          ClientSurfaceRejectionReason.structuralViolation,
          reason: '$override',
        );
      }
    });

    test('refuses field presentations on a report screen', () {
      final screen = _screen(
        overrides: {
          'kind': 'report',
          'report': 'acme.report.aging',
          'field_presentations': {
            'total': {'widget': 'money'},
          },
        },
      )..remove('definition');
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(screens: <Object?>[screen]),
          ],
        ),
      );
      expect(result.isUsable, isFalse);
      expect(
        result.rejections.single.reason,
        ClientSurfaceRejectionReason.structuralViolation,
      );
    });

    test('admits a valid form and report screen', () {
      final form = _screen(
        id: 'acme.orders.admin.screen.create',
        overrides: {'kind': 'form', 'mode': 'create'},
      );
      final report =
          _screen(
              id: 'acme.orders.admin.screen.aging',
              overrides: {'kind': 'report', 'report': 'acme.report.aging'},
            )
            ..remove('definition')
            ..remove('field_presentations');

      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              navigation: <Object?>[
                _navigation(screen: 'acme.orders.admin.screen.create'),
                _navigation(
                  id: 'acme.orders.admin.nav.aging',
                  screen: 'acme.orders.admin.screen.aging',
                ),
              ],
              screens: <Object?>[form, report],
            ),
          ],
        ),
      );

      expect(result.rejections, isEmpty);
      final screens = result.manifest!.surfaces.single.screens;
      expect(screens.first.mode, ClientFormMode.create);
      expect(screens.last.kind, ClientScreenKind.report);
    });
  });

  group('bounds and closed objects', () {
    test('refuses undeclared members anywhere in a surface', () {
      final overrides = <Map<String, Object?>>[
        {'surface': 'x'},
      ];
      for (final _ in overrides) {
        final result = _interpret(
          _manifest(
            surfaces: <Object?>[
              _surface(overrides: {'route': '/admin/orders'}),
            ],
          ),
        );
        expect(result.isUsable, isFalse);
        expect(
          result.rejections.single.reason,
          ClientSurfaceRejectionReason.structuralViolation,
        );
      }

      final screenResult = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              screens: <Object?>[
                _screen(overrides: {'template': 'orders.twig'}),
              ],
            ),
          ],
        ),
      );
      expect(screenResult.isUsable, isFalse);
      expect(
        screenResult.rejections.single.reason,
        ClientSurfaceRejectionReason.structuralViolation,
      );
    });

    test('enforces collection and capability bounds', () {
      final tooManyCapabilities = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              overrides: {
                'required_capabilities': <Object?>[
                  for (var index = 0; index < 33; index++)
                    'acme.capability.n$index',
                ],
              },
            ),
          ],
        ),
      );
      expect(tooManyCapabilities.isUsable, isFalse);

      final duplicateCapability = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              overrides: {
                'required_capabilities': <Object?>[
                  'acme.orders.read',
                  'acme.orders.read',
                ],
              },
            ),
          ],
        ),
      );
      expect(
        duplicateCapability.rejections.single.reason,
        ClientSurfaceRejectionReason.duplicateIdentifier,
      );

      final orderOutOfRange = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(overrides: {'order': 100001}),
          ],
        ),
      );
      expect(orderOutOfRange.isUsable, isFalse);
    });

    test('refuses label text outside its declared bounds', () {
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              overrides: {
                'label': {'default': 'x' * 501},
              },
            ),
          ],
        ),
      );
      expect(result.isUsable, isFalse);
      expect(
        result.rejections.single.reason,
        ClientSurfaceRejectionReason.structuralViolation,
      );
    });
  });

  group('localized text', () {
    test('resolves the most specific matching tag then falls back', () {
      final text = LocalizedText(
        defaultText: 'Orders',
        translations: {'en-NA': 'Orders NA', 'af': 'Bestellings'},
      );
      expect(text.resolve('en-NA'), 'Orders NA');
      expect(text.resolve('EN-na'), 'Orders NA');
      expect(text.resolve('af-ZA'), 'Bestellings');
      expect(text.resolve('de'), 'Orders');
      expect(text.resolve(null), 'Orders');
      expect(text.resolve('en'), 'Orders');
    });

    test('rejects unbounded or malformed translations', () {
      expect(() => LocalizedText(defaultText: ''), throwsArgumentError);
      expect(() => LocalizedText(defaultText: 'x' * 501), throwsArgumentError);
      expect(
        () => LocalizedText(
          defaultText: 'Orders',
          translations: {'not a tag': 'x'},
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalizedText(
          defaultText: 'Orders',
          translations: {
            for (var index = 0; index < 17; index++) 'l$index': 'x',
          },
        ),
        throwsArgumentError,
      );
    });

    test('carries translations through interpretation immutably', () {
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              overrides: {
                'label': {
                  'default': 'Orders',
                  'translations': {'af': 'Bestellings'},
                },
              },
            ),
          ],
        ),
      );
      final label = result.manifest!.surfaces.single.label;
      expect(label.resolve('af'), 'Bestellings');
      expect(
        () => label.translations['de'] = 'Bestellungen',
        throwsUnsupportedError,
      );
    });
  });

  group('explicit null', () {
    test('refuses a forbidden member present carrying no value', () {
      // A `false` subschema forbids the member outright, so presence is the
      // violation whatever it carries. Reading null as absent would let every
      // per-kind prohibition be smuggled past.
      final forbidden = <({String kind, String member})>[
        (kind: 'collection', member: 'mode'),
        (kind: 'collection', member: 'report'),
        (kind: 'record', member: 'view'),
        (kind: 'record', member: 'mode'),
        (kind: 'record', member: 'report'),
        (kind: 'form', member: 'view'),
        (kind: 'form', member: 'report'),
        (kind: 'document', member: 'mode'),
        (kind: 'document', member: 'report'),
        (kind: 'report', member: 'definition'),
        (kind: 'report', member: 'view'),
        (kind: 'report', member: 'mode'),
        (kind: 'report', member: 'field_presentations'),
      ];

      for (final testCase in forbidden) {
        final overrides = <String, Object?>{
          'kind': testCase.kind,
          testCase.member: null,
        };
        if (testCase.kind == 'form') {
          overrides['mode'] = 'create';
        }
        if (testCase.kind == 'document') {
          overrides['view'] = 'lines';
        }
        if (testCase.kind == 'report') {
          overrides['report'] = 'acme.report.aging';
        }
        final screen = _screen(overrides: overrides);
        if (testCase.kind == 'report') {
          screen.remove('definition');
          screen.remove('field_presentations');
          screen[testCase.member] = null;
        }
        final reason = '${testCase.kind}.${testCase.member}';
        expect(
          screen.containsKey(testCase.member),
          isTrue,
          reason: '$reason: the fixture must declare the member',
        );

        final result = _interpret(
          _manifest(
            surfaces: <Object?>[
              _surface(screens: <Object?>[screen]),
            ],
          ),
        );
        expect(result.isUsable, isFalse, reason: reason);
        expect(
          result.rejections.single.reason,
          ClientSurfaceRejectionReason.structuralViolation,
          reason: reason,
        );
      }
    });

    test('refuses any optional member present carrying no value', () {
      final nulled = <String, Map<String, Object?>>{
        'surface description': {'description': null},
        'surface label translations': {
          'label': {'default': 'Orders', 'translations': null},
        },
      };
      for (final entry in nulled.entries) {
        final result = _interpret(
          _manifest(surfaces: <Object?>[_surface(overrides: entry.value)]),
        );
        expect(result.isUsable, isFalse, reason: entry.key);
        expect(
          result.rejections.single.reason,
          ClientSurfaceRejectionReason.structuralViolation,
          reason: entry.key,
        );
      }

      final nullIcon = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              navigation: <Object?>[
                _navigation(overrides: {'icon': null}),
              ],
            ),
          ],
        ),
      );
      expect(nullIcon.isUsable, isFalse);
      expect(nullIcon.notices, isEmpty);

      final nullEmphasis = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              screens: <Object?>[
                _screen(
                  overrides: {
                    'field_presentations': {
                      'order_number': {'widget': 'text', 'emphasis': null},
                    },
                  },
                ),
              ],
            ),
          ],
        ),
      );
      expect(nullEmphasis.isUsable, isFalse);
      expect(nullEmphasis.notices, isEmpty);
    });
  });

  group('optional hints reject malformed values', () {
    test('a hint carrying non-text is refused, never downgraded', () {
      // Forgiving an unknown word keeps a surface usable across contract
      // revisions. Forgiving arbitrary JSON would hide a broken document.
      final malformed = <Object?>[
        12345,
        <Object?>['a', 'b'],
        {'k': 'v'},
        true,
      ];
      for (final value in malformed) {
        final iconResult = _interpret(
          _manifest(
            surfaces: <Object?>[
              _surface(
                navigation: <Object?>[
                  _navigation(overrides: {'icon': value}),
                ],
              ),
            ],
          ),
        );
        expect(iconResult.isUsable, isFalse, reason: 'icon = $value');
        expect(iconResult.notices, isEmpty, reason: 'icon = $value');
        expect(
          iconResult.rejections.single.reason,
          ClientSurfaceRejectionReason.structuralViolation,
          reason: 'icon = $value',
        );

        final widthResult = _interpret(
          _manifest(
            surfaces: <Object?>[
              _surface(
                screens: <Object?>[
                  _screen(
                    overrides: {
                      'field_presentations': {
                        'order_number': {'widget': 'text', 'width': value},
                      },
                    },
                  ),
                ],
              ),
            ],
          ),
        );
        expect(widthResult.isUsable, isFalse, reason: 'width = $value');
        expect(widthResult.notices, isEmpty, reason: 'width = $value');
      }
    });

    test('a hint carrying an unknown word is still forgiven', () {
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              navigation: <Object?>[
                _navigation(overrides: {'icon': 'spaceship'}),
              ],
            ),
          ],
        ),
      );
      expect(result.isUsable, isTrue);
      expect(result.notices, hasLength(1));
    });
  });

  group('numeric and text bounds match the schema', () {
    test('accepts an integer written with a fractional zero', () {
      // JSON Schema calls any number with no fractional part an integer.
      final result = _interpreter.interpretJson(
        '{"\$schema":"${ClientSurfaceInterpreter.schemaId}",'
        '"schema_version":1,"manifest_id":"acme.orders.client",'
        '"owner":{"extension":"acme/orders","version":"1.0.0",'
        '"checksum":"sha256:${'1' * 64}"},'
        '"runtime":{"generation":42.0,"checksum":"sha256:${'2' * 64}"},'
        '"required_contracts":[{"id":"kumwe.client-surface",'
        '"version_range":"^1.0.0"}],'
        '"surfaces":[{"id":"acme.orders.admin.workspace",'
        '"audience":"administrator","kind":"workspace",'
        '"label":{"default":"Orders"},"order":10.0,'
        '"required_capabilities":[],"unsupported_behavior":"hide",'
        '"navigation":[{"id":"acme.orders.admin.nav.orders",'
        '"label":{"default":"Orders"},'
        '"screen":"acme.orders.admin.screen.orders","order":0,'
        '"required_capabilities":[]}],'
        '"screens":[{"id":"acme.orders.admin.screen.orders",'
        '"kind":"collection","label":{"default":"Orders"},"order":10,'
        '"required_capabilities":[],"required_operations":["browse"],'
        '"definition":"acme.order"}]}]}',
      );
      expect(result.rejections, isEmpty);
      expect(result.manifest!.runtime.generation, 42);
      expect(result.manifest!.surfaces.single.order, 10);
    });

    test('refuses a fractional number where an integer is declared', () {
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(overrides: {'order': 10.5}),
          ],
        ),
      );
      expect(result.isUsable, isFalse);
      expect(
        result.rejections.single.reason,
        ClientSurfaceRejectionReason.structuralViolation,
      );
    });

    test('non-finite numbers are refused before the interpreter sees them', () {
      // The JSON value layer rejects them, so the interpreter never has to.
      expect(
        () => _interpret(
          _manifest(
            surfaces: <Object?>[
              _surface(overrides: {'order': double.nan}),
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('measures text length in code points, not UTF-16 units', () {
      // A non-BMP label costs two UTF-16 units per character, so counting
      // units would refuse a valid label at roughly half its bound.
      String label(int codePoints) => '\u{1F600}' * codePoints;
      expect(label(500).length, 1000, reason: 'the fixture must be non-BMP');

      final atBound = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              overrides: {
                'label': {'default': label(500)},
              },
            ),
          ],
        ),
      );
      expect(atBound.isUsable, isTrue);

      final overBound = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              overrides: {
                'label': {'default': label(501)},
              },
            ),
          ],
        ),
      );
      expect(overBound.isUsable, isFalse);
    });

    test('bounds translation language tags', () {
      // Subtags are capped at eight characters each, so a long tag has to be
      // built from several of them to stay inside the declared grammar.
      String tag(int trailing) => 'en${'-aaaaaaaa' * 3}-${'a' * trailing}';
      expect(tag(5).length, 35);
      expect(tag(6).length, 36);

      final atBound = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              overrides: {
                'label': {
                  'default': 'Orders',
                  'translations': {tag(5): 'Orders'},
                },
              },
            ),
          ],
        ),
      );
      expect(atBound.isUsable, isTrue);

      final overBound = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              overrides: {
                'label': {
                  'default': 'Orders',
                  'translations': {tag(6): 'Orders'},
                },
              },
            ),
          ],
        ),
      );
      expect(overBound.isUsable, isFalse);
    });

    test('accepts collections exactly at their declared ceiling', () {
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              overrides: {
                'order': 100000,
                'required_capabilities': <Object?>[
                  for (var index = 0; index < 32; index++)
                    'acme.capability.n$index',
                ],
              },
              screens: <Object?>[
                _screen(
                  overrides: {
                    'required_operations': <Object?>[
                      for (final operation in ClientBusinessOperation.values)
                        operation.wireName,
                    ],
                    'field_presentations': {
                      for (var index = 0; index < 64; index++)
                        'field_n$index': {'widget': 'text'},
                    },
                  },
                ),
              ],
            ),
          ],
        ),
      );

      expect(result.rejections, isEmpty);
      final screen = result.manifest!.surfaces.single.screens.single;
      expect(screen.requiredOperations, hasLength(13));
      expect(screen.fieldPresentations, hasLength(64));
      expect(result.manifest!.surfaces.single.order, 100000);
    });

    test('refuses one entry beyond a declared ceiling', () {
      final result = _interpret(
        _manifest(
          surfaces: <Object?>[
            _surface(
              screens: <Object?>[
                _screen(
                  overrides: {
                    'field_presentations': {
                      for (var index = 0; index < 65; index++)
                        'field_n$index': {'widget': 'text'},
                    },
                  },
                ),
              ],
            ),
          ],
        ),
      );
      expect(result.isUsable, isFalse);
    });
  });

  group('encoded source', () {
    test(
      'refuses a manifest beyond the declared byte bound before parsing',
      () {
        final result = _interpreter.interpretJson('{}', maxBytes: 1);
        expect(result.manifest, isNull);
        expect(result.rejections.single.message, contains('byte bound'));
      },
    );

    test('refuses source that is not a JSON object', () {
      for (final source in ['not json', '[]', '42']) {
        final result = _interpreter.interpretJson(source);
        expect(result.manifest, isNull, reason: source);
        expect(result.rejections, hasLength(1), reason: source);
      }
    });

    test('reads the shipped examples through the bounded entry point', () {
      final source = File(
        'contracts/examples/minimal.client-surface.json',
      ).readAsStringSync();
      final result = _interpreter.interpretJson(source);
      expect(result.rejections, isEmpty);
      expect(result.isUsable, isTrue);
    });
  });

  test('every closed vocabulary value round-trips through interpretation', () {
    final widgets = ClientFieldWidget.values;
    final icons = ClientNavigationIcon.values;

    final screens = <Object?>[
      _screen(
        id: 'acme.orders.admin.screen.collection',
        overrides: {
          'kind': 'collection',
          'field_presentations': {
            for (var index = 0; index < widgets.length; index++)
              'field_n$index': {
                'widget': widgets[index].wireName,
                'emphasis': ClientFieldEmphasis
                    .values[index % ClientFieldEmphasis.values.length]
                    .wireName,
                'width': ClientFieldWidth
                    .values[index % ClientFieldWidth.values.length]
                    .wireName,
              },
          },
        },
      ),
      _screen(
        id: 'acme.orders.admin.screen.record',
        overrides: {'kind': 'record'},
      )..remove('field_presentations'),
      _screen(
        id: 'acme.orders.admin.screen.form',
        overrides: {'kind': 'form', 'mode': 'update'},
      ),
      _screen(
        id: 'acme.orders.admin.screen.document',
        overrides: {'kind': 'document', 'view': 'lines'},
      ),
      _screen(
          id: 'acme.orders.admin.screen.report',
          overrides: {'kind': 'report', 'report': 'acme.report.aging'},
        )
        ..remove('definition')
        ..remove('field_presentations'),
    ];

    final navigation = <Object?>[
      for (var index = 0; index < icons.length; index++)
        _navigation(
          id: 'acme.orders.admin.nav.n$index',
          screen: 'acme.orders.admin.screen.collection',
          overrides: {'icon': icons[index].wireName},
        ),
    ];

    final result = _interpret(
      _manifest(
        surfaces: <Object?>[
          _surface(navigation: navigation, screens: screens),
          _surface(
            id: 'acme.orders.portal.module',
            overrides: {
              'audience': 'portal',
              'kind': 'module',
              'unsupported_behavior': 'show_unavailable',
            },
            navigation: <Object?>[
              _navigation(
                id: 'acme.orders.portal.nav.orders',
                screen: 'acme.orders.portal.screen.orders',
              ),
            ],
            screens: <Object?>[_screen(id: 'acme.orders.portal.screen.orders')],
          ),
        ],
      ),
    );

    expect(result.rejections, isEmpty);
    expect(result.notices, isEmpty);

    final admin = result.manifest!.surfaces.first;
    expect(
      admin.screens.map((screen) => screen.kind).toSet(),
      ClientScreenKind.values.toSet(),
      reason: 'every screen kind must be reachable',
    );
    expect(
      admin.screens.first.fieldPresentations.values
          .map((presentation) => presentation.widget)
          .toSet(),
      ClientFieldWidget.values.toSet(),
      reason: 'every widget must be reachable',
    );
    expect(
      admin.navigation.map((item) => item.icon).toSet(),
      ClientNavigationIcon.values.toSet(),
      reason: 'every icon must be reachable',
    );

    final portal = result.manifest!.surfaces.last;
    expect(portal.audience, ClientSurfaceAudience.portal);
    expect(portal.kind, ClientSurfaceKind.module);
    expect(
      portal.unsupportedBehavior,
      ClientUnsupportedBehavior.showUnavailable,
    );
    expect(admin.audience, ClientSurfaceAudience.administrator);
    expect(admin.kind, ClientSurfaceKind.workspace);
    expect(admin.unsupportedBehavior, ClientUnsupportedBehavior.hide);
    expect(
      admin.screens
          .firstWhere((screen) => screen.kind == ClientScreenKind.form)
          .mode,
      ClientFormMode.update,
    );
  });

  test('admitted collections are immutable', () {
    final manifest = _interpret(_manifest()).manifest!;
    final surface = manifest.surfaces.single;
    expect(() => manifest.surfaces.add(surface), throwsUnsupportedError);
    expect(
      () => surface.requiredCapabilities.add('acme.orders.write'),
      throwsUnsupportedError,
    );
    expect(
      () => surface.screens.single.requiredOperations.add(
        ClientBusinessOperation.delete,
      ),
      throwsUnsupportedError,
    );
  });
}
