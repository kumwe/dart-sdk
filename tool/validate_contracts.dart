import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';

import 'src/contract_repository_semantics.dart';

void main(List<String> arguments) {
  final roots = arguments.isEmpty ? const <String>['contracts'] : arguments;
  final List<File> files;
  try {
    files = _collectJsonFiles(roots);
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  }
  if (files.isEmpty) {
    stderr.writeln('No JSON contract documents were found.');
    exitCode = 1;
    return;
  }

  final documents = <_LoadedDocument>[];
  var failures = 0;
  for (final file in files) {
    try {
      documents.add(
        _LoadedDocument(file, KumweJsonObject.parse(file.readAsStringSync())),
      );
    } on FileSystemException catch (error) {
      stderr.writeln('${file.path}: unable to read document: ${error.message}');
      failures++;
    } on FormatException catch (error) {
      stderr.writeln('${file.path}: invalid JSON object: ${error.message}');
      failures++;
    }
  }

  final catalog = JsonSchemaCatalog();
  for (final loaded in documents.where((item) => item.isJsonSchema)) {
    try {
      catalog.add(loaded.uri, loaded.document);
    } on ArgumentError catch (error) {
      stderr.writeln(
        '${loaded.file.path}: schema registration failed: ${error.message}',
      );
      failures++;
    }
  }

  final schemaValidator = JsonSchemaContractValidator(catalog);
  const semanticValidator = ContractRepositorySemanticValidator();
  for (final loaded in documents) {
    final ContractValidationResult result;
    if (loaded.isOpenApi) {
      result = OpenApiContractValidator().validate(loaded.document);
    } else if (loaded.isJsonSchema) {
      result = schemaValidator.validateSchema(
        loaded.document,
        documentUri: loaded.uri,
      );
    } else {
      final schemaReference = loaded.document[r'$schema'];
      final resolved = schemaReference is String
          ? catalog.resolve(baseUri: loaded.uri, reference: schemaReference)
          : null;
      if (resolved == null) {
        stderr.writeln(
          '${loaded.file.path}: cannot resolve the instance schema declared by \$schema.',
        );
        failures++;
        continue;
      }
      final schemaResult = schemaValidator.validateResolvedInstance(
        KumweJsonValue.from(loaded.document.value),
        schema: resolved,
      );
      final semanticResult = semanticValidator.validateInstance(
        loaded.document,
        declaredSchema: resolved.document,
      );
      result = _combineResults(schemaResult, semanticResult);
    }
    if (!result.isValid) {
      for (final issue in result.issues) {
        stderr.writeln('${loaded.file.path}: $issue');
      }
      failures += result.issues.length;
    }
  }

  if (failures > 0) {
    stderr.writeln(
      'Contract validation failed with $failures issue${failures == 1 ? '' : 's'}.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('Validated ${documents.length} JSON contract documents.');
}

ContractValidationResult _combineResults(
  ContractValidationResult first,
  ContractValidationResult second,
) {
  final issues = <ContractValidationIssue>[...first.issues, ...second.issues]
    ..sort((left, right) {
      final byPath = left.path.compareTo(right.path);
      return byPath != 0 ? byPath : left.message.compareTo(right.message);
    });
  return ContractValidationResult(issues);
}

List<File> _collectJsonFiles(List<String> roots) {
  final files = <File>[];
  for (final root in roots) {
    final type = FileSystemEntity.typeSync(root, followLinks: false);
    if (type == FileSystemEntityType.file) {
      if (root.toLowerCase().endsWith('.json')) {
        files.add(File(root));
      }
      continue;
    }
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException('$root: contract path does not exist.');
    }
    for (final entity in Directory(
      root,
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
        files.add(entity);
      }
    }
  }
  files.sort(
    (left, right) => left.absolute.path.compareTo(right.absolute.path),
  );
  return files;
}

final class _LoadedDocument {
  const _LoadedDocument(this.file, this.document);

  final File file;
  final KumweJsonObject document;

  Uri get uri => file.absolute.uri;

  bool get isOpenApi => document['openapi'] is String;

  bool get isJsonSchema {
    return document[r'$schema'] ==
        'https://json-schema.org/draft/2020-12/schema';
  }
}
