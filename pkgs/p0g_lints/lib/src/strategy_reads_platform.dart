import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Strategies decide with `available(facts)`. `kIsWeb` and `Platform` say
/// what Dart was compiled for, not what this place can do: WebUI reports web,
/// AERA reports Linux, and neither says whether there is root.
///
/// Applies inside any class that extends `Strategy` (directly or through
/// `ReadStrategy` / `WriteStrategy`) and to every file under a
/// `lib/src/strategy/` folder.
class StrategyReadsPlatform extends AnalysisRule {
  static const code = LintCode(
    'strategy_reads_platform',
    "A strategy can't read '{0}'.",
    correctionMessage:
        'Decide in available(facts): add or use a fact (core/lib/src/facts/) '
        'and list it in requires.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Names that report the compile target, and the library each comes from.
  static const banned = {
    'kIsWeb': 'package:flutter/',
    'defaultTargetPlatform': 'package:flutter/',
    'TargetPlatform': 'package:flutter/',
    'Platform': 'dart:io',
  };

  StrategyReadsPlatform()
    : super(
        name: 'strategy_reads_platform',
        description: 'Strategies never read kIsWeb or Platform.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final path = context.definingUnit.file.path.replaceAll(r'\', '/');
    registry.addSimpleIdentifier(
      this,
      _Visitor(this, wholeFile: path.contains('/lib/src/strategy/')),
    );
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, {required this.wholeFile});

  final StrategyReadsPlatform rule;
  final bool wholeFile;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final from = StrategyReadsPlatform.banned[node.name];
    if (from == null || node.inDeclarationContext()) return;
    final uri = node.element?.library?.uri.toString();
    if (uri == null || !uri.startsWith(from)) return;
    if (wholeFile || _inStrategy(node)) {
      rule.reportAtNode(node, arguments: [node.name]);
    }
  }

  static bool _inStrategy(AstNode node) {
    final declaration = node.thisOrAncestorOfType<ClassDeclaration>();
    final element = declaration?.declaredFragment?.element;
    if (element == null) return false;
    return element.allSupertypes.any((t) => t.element.name == 'Strategy');
  }
}
