/// Acting on a [Route]: the one place every input ends up.
library;

import 'package:flutter/widgets.dart';

import '../core/core.dart';
import 'binfire_controller.dart';
import 'sheets.dart';

/// A user-facing message for a route error code.
String routeErrorMessage(String code) => switch (code) {
      ErrorCodes.tooLarge => 'This link is too large to open.',
      ErrorCodes.unknownApp => "This link is for an app binfire doesn't know.",
      ErrorCodes.badLink => 'This binfire link is malformed.',
      ErrorCodes.invalidCid => "This binfire link doesn't contain a valid document ID.",
      ErrorCodes.unknownLink => "binfire doesn't recognise this link.",
      _ => 'Something went wrong ($code).',
    };

/// Performs [route]: opens the app, or shows the text or error sheet.
Future<void> performRoute(BuildContext context, BinfireController controller, LinkRoute route) async {
  switch (route.action) {
    case RouteAction.openApp:
      controller.openApp(route.app!, route.url!);
    case RouteAction.showText:
      await showTextSheet(context, route.text!);
    case RouteAction.error:
      await showErrorSheet(context, routeErrorMessage(route.error!));
    case RouteAction.loadCid:
      await showErrorSheet(context, 'Opening HashBin documents is coming in M3.');
    case RouteAction.openSite:
      await showErrorSheet(context, 'Packaged sites are coming in M6.');
  }
}
