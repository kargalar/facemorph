import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalUrl(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
