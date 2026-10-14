import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/passage.dart';
import '../../../models/toll_post.dart';
import '../../../models/toll_tariff.dart';
import '../../../services/passage_service.dart';
import '../../../services/toll_catalog_service.dart';
import '../widgets/qr_scan_dialog.dart';

/// Vérification d'un justificatif par l'agent : saisie/collage du code QR,
/// contrôle des informations, puis autorisation ou refus du passage.
/// (La lecture par caméra pourra s'ajouter plus tard ; la saisie manuelle
/// sert aussi de solution de secours.)
class AgentVerificationScreen extends StatefulWidget {
  const AgentVerificationScreen({
    super.key,
    required this.passageService,
    required this.catalogService,
  });

  final PassageServiceBase passageService;
  final TollCatalogServiceBase catalogService;

  @override
  State<AgentVerificationScreen> createState() =>
      _AgentVerificationScreenState();
}

class _AgentVerificationScreenState extends State<AgentVerificationScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _message;
  ScannedReceipt? _scanned;
  List<Passage> _history = const [];
  List<TollPost> _posts = const [];

  /// Poste où l'agent travaille (aucun lien agent-poste n'existe encore :
  /// c'est l'agent qui l'indique).
  TollPost? _controlPost;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadPosts();
  }

  /// La caméra n'est proposée que là où le paquet de lecture la prend en
  /// charge ; ailleurs (Windows, Linux) la saisie manuelle reste disponible.
  bool get _cameraSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> _scanWithCamera() async {
    final code = await showQrScanDialog(context);
    if (code == null || !mounted) return;
    _codeController.text = code;
    await _scan();
  }

  Future<void> _loadPosts() async {
    try {
      final posts = await widget.catalogService.getTollPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        if (posts.length == 1) _controlPost = posts.first;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await widget.passageService.getMyPassages();
      if (!mounted) return;
      setState(() => _history = history);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _scan() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Saisissez ou collez le code du justificatif.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _scanned = null;
    });
    try {
      final scanned = await widget.passageService.scanReceipt(
        code,
        postId: _controlPost?.id,
      );
      if (!mounted) return;
      setState(() => _scanned = scanned);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askRefusalReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refuser le passage'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Motif du refus'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
  }

  Future<void> _decide({required bool authorized}) async {
    final scanned = _scanned;
    if (scanned == null) return;
    String? reason;
    if (!authorized) {
      reason = await _askRefusalReason();
      if (reason == null) return;
      if (reason.isEmpty) {
        setState(() => _error = 'Le motif du refus est obligatoire.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.passageService.decidePassage(
        scanned.qrCode,
        authorized: authorized,
        reason: reason,
        postId: scanned.postId,
      );
      if (!mounted) return;
      setState(() {
        _message = authorized
            ? 'Passage autorisé. Vous pouvez lever la barrière.'
            : 'Passage refusé.';
        _scanned = null;
        _codeController.clear();
      });
      await _loadHistory();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _tripLabel(TripType type) =>
      type == TripType.longueDistance ? 'Longue distance' : 'Demi-trajet';

  String _formatDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scanned = _scanned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        if (_message != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Text(_message!),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vérifier un justificatif',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<TollPost>(
                  initialValue: _controlPost,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Poste de contrôle',
                    helperText:
                        'Le poste où vous travaillez. Sans choix, le prochain '
                        'poste du trajet est utilisé.',
                  ),
                  items: _posts
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            p.sequence != null ? '${p.sequence}. ${p.name}' : p.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _controlPost = value),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Code du justificatif (RP-…)',
                          prefixIcon: Icon(Icons.qr_code_scanner),
                        ),
                        onSubmitted: (_) => _scan(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_cameraSupported) ...[
                      IconButton.filledTonal(
                        tooltip: 'Scanner avec la caméra',
                        onPressed: _busy ? null : _scanWithCamera,
                        icon: const Icon(Icons.photo_camera_outlined),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilledButton(
                      onPressed: _busy ? null : _scan,
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Vérifier'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (scanned != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scanned.registrationNumber,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${scanned.brand} ${scanned.model}'),
                  Text(
                    'Catégorie : ${scanned.categoryCode} — ${scanned.categoryName}',
                  ),
                  Text('Poste de contrôle : ${scanned.postName}'),
                  Text(
                    'Trajet jusqu’à : ${scanned.destinationName} — '
                    '${scanned.postsCrossed} poste(s), '
                    '${scanned.passedCount} déjà franchi(s)',
                  ),
                  Text('Trajet : ${_tripLabel(scanned.tripType)}'),
                  Text(
                    'Montant payé : ${scanned.amountDue.toStringAsFixed(2)} ${scanned.currency}',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Comparez ces informations avec le véhicule présent au poste.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _decide(authorized: true),
                        icon: const Icon(Icons.check),
                        label: const Text('Autoriser le passage'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _decide(authorized: false),
                        icon: const Icon(Icons.block),
                        label: const Text('Refuser'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Mes vérifications',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 12),
        if (_history.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucune vérification pour le moment.'),
            ),
          )
        else
          ..._history.map(
            (p) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(
                  p.result == PassageResult.autorise
                      ? Icons.check_circle_outline
                      : Icons.block,
                  color: p.result == PassageResult.autorise
                      ? Colors.green
                      : Colors.red,
                ),
                title: Text(p.result.label),
                subtitle: Text(
                  '${_formatDate(p.createdAt)}'
                  '${p.refusalReason != null ? '\nMotif : ${p.refusalReason}' : ''}',
                ),
                isThreeLine: p.refusalReason != null,
              ),
            ),
          ),
      ],
    );
  }
}
