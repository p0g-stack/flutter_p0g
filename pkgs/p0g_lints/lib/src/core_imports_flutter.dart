import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// `core/` (a package named `*_core`) is plain Dart: the CLI runs it on the
/// Dart VM, where Flutter does not exist.
class CoreImportsFlutter extends AnalysisRule {
  static const code = LintCode(
    'core_imports_flutter',
    "The core package can't import '{0}'.",
    correctionMessage:
        'Keep core plain Dart; put Flutter code in app/, or pass what core '
        'needs in as a value.',
    severity: DiagnosticSeverity.WARNING,
  );

  CoreImportsFlutter()
    : super(
        name: 'core_imports_flutter',
        description: 'A *_core package never imports Flutter or dart:ui.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (!isCorePackage(context)) return;
    final visitor = _Visitor(this);
    registry
      ..addImportDirective(this, visitor)
      ..addExportDirective(this, visitor);
  }

  /// Whether the file being analyzed belongs to a package named `*_core`.
  static bool isCorePackage(RuleContext context) {
    final root = context.package?.root;
    if (root == null) return false;
    try {
      final pubspec = root.getFile('pubspec.yaml');
      final name = RegExp(
        r'^name:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec.readAsStringSync())?.group(1);
      return name != null && name.endsWith('_core');
    } on Object {
      return false;
    }
  }

  static bool isFlutter(String uri) =>
      uri == 'dart:ui' ||
      uri.startsWith('dart:ui_') ||
      uri.startsWith('package:flutter/') ||
      uri.startsWith('package:flutter_test/') ||
      uri.startsWith('package:flutter_web_plugins/');
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final CoreImportsFlutter rule;

  void _check(NamespaceDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null && CoreImportsFlutter.isFlutter(uri)) {
      rule.reportAtNode(node.uri, arguments: [uri]);
    }
  }

  @override
  void visitImportDirective(ImportDirective node) => _check(node);

  @override
  void visitExportDirective(ExportDirective node) => _check(node);
}
