import 'package:flutter/widgets.dart';

import '../places/places.dart';
{{#sample}}import 'hello_panel.dart';
{{/sample}}// p0g:imports (bricks insert imports above this line)

/// Builds one service's panel in the place of [kind] the user picked.
typedef PanelBuilder = Widget Function(Places places, String kind);

/// One panel per service, in page order.
const List<PanelBuilder> defaultPanels = [
{{#sample}}  HelloPanel.inPlace,
{{/sample}}  // p0g:panels (bricks insert panels above this line)
];
