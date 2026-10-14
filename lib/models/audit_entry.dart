class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.targetEntity,
    this.targetId,
    required this.details,
    required this.createdAt,
    this.userName,
    this.userRole,
  });

  final String id;

  /// 'insert' ou 'update' (opération SQL).
  final String action;

  /// Nom de la table concernée (ex. 'transactions').
  final String targetEntity;
  final String? targetId;
  final Map<String, dynamic> details;
  final DateTime createdAt;

  /// Nul pour une action automatique (sans session utilisateur).
  final String? userName;
  final String? userRole;

  static const entityLabels = {
    'transactions': 'Transaction',
    'payments': 'Paiement',
    'receipts': 'Justificatif',
    'passages': 'Passage',
    'exemptions': 'Exemption',
    'prepaid_accounts': 'Compte prépayé',
    'account_movements': 'Mouvement de compte',
    'toll_posts': 'Poste de péage',
    'vehicle_categories': 'Catégorie',
    'toll_tariffs': 'Tarif',
    'profiles': 'Profil',
    'app_settings': 'Réglage',
  };

  String get entityLabel => entityLabels[targetEntity] ?? targetEntity;

  String get actionLabel => action == 'insert' ? 'Création' : 'Modification';

  /// Détails lisibles : « status : initiee → payee » ou « amount_due : 5.0 ».
  String get detailsText {
    if (details.isEmpty) return '';
    return details.entries
        .map((entry) {
          final value = entry.value;
          if (value is Map && value.containsKey('from')) {
            return '${entry.key} : ${value['from']} → ${value['to']}';
          }
          return '${entry.key} : $value';
        })
        .join('\n');
  }

  factory AuditEntry.fromMap(Map<String, dynamic> map) {
    final details = map['details'];
    return AuditEntry(
      id: (map['id'] ?? '').toString(),
      action: (map['action'] ?? '').toString(),
      targetEntity: (map['target_entity'] ?? '').toString(),
      targetId: map['target_id']?.toString(),
      details: details is Map<String, dynamic> ? details : const {},
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
      userName: map['user_name']?.toString(),
      userRole: map['user_role']?.toString(),
    );
  }
}
