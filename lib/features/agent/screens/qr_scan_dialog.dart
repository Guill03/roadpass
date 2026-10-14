import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Demande l'autorisation d'utiliser la caméra (explication, puis demande
/// du système), puis ouvre la lecture du QR. Renvoie le texte du premier code
/// lu, ou null si l'agent annule ou refuse l'accès à la caméra. La saisie
/// manuelle du code reste disponible dans l'écran.
Future<String?> showQrScanDialog(BuildContext context) async {
  final allowed = await _ensureCameraPermission(context);
  if (!allowed || !context.mounted) return null;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _QrScanDialog(),
  );
}

/// Sur Android et iOS, on demande l'autorisation nous-mêmes. Sur le web et
/// macOS, c'est le navigateur ou le système qui affiche sa propre demande à
/// l'ouverture de la caméra.
bool get _managesPermissionItself =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<bool> _ensureCameraPermission(BuildContext context) async {
  if (!_managesPermissionItself) return true;

  var status = await Permission.camera.status;
  if (status.isGranted) return true;

  // Première demande (ou refus simple) : on explique avant de demander.
  if (status.isDenied) {
    if (!context.mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Autoriser la caméra ?'),
        content: const Text(
          'RoadPass utilise la caméra uniquement pour lire le code QR des '
          'justificatifs. Aucune photo n’est enregistrée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (proceed != true) return false;
    status = await Permission.camera.request();
    if (status.isGranted) return true;
  }

  // Refus définitif (ou restreint) : seul le réglage du téléphone peut changer ça.
  if (!context.mounted) return false;
  final permanent = status.isPermanentlyDenied || status.isRestricted;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Accès à la caméra refusé'),
      content: Text(
        permanent
            ? 'Pour scanner un justificatif, autorisez la caméra dans les '
                  'réglages de l’application. Vous pouvez aussi saisir le code '
                  'à la main.'
            : 'Sans la caméra, vous pouvez saisir le code du justificatif à '
                  'la main, ou réessayer et autoriser l’accès.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
        if (permanent)
          FilledButton(
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
            child: const Text('Ouvrir les réglages'),
          ),
      ],
    ),
  );
  return false;
}

class _QrScanDialog extends StatefulWidget {
  const _QrScanDialog();

  @override
  State<_QrScanDialog> createState() => _QrScanDialogState();
}

class _QrScanDialogState extends State<_QrScanDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scanner le justificatif'),
      content: SizedBox(
        width: 320,
        height: 320,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: MobileScanner(controller: _controller, onDetect: _onDetect),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
      ],
    );
  }
}