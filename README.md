# RoadPass

Socle Flutter multi-plateforme pour une future plateforme de gestion des passages aux postes de péage.

## Lancer le projet

```bash
flutter pub get
flutter run -d chrome
# ou : flutter run -d windows
```

Pour utiliser Supabase, passe les valeurs au lancement sans les enregistrer dans
le code source :

```powershell
flutter run -d chrome `
	--dart-define=SUPABASE_URL=https://<project-ref>.supabase.co `
	--dart-define=SUPABASE_ANON_KEY=sb_publishable_...
```

Vérification :

```bash
flutter analyze
flutter test
```

## Comptes de démonstration

Tous les comptes utilisent le mot de passe `RoadPass123!`.

| Espace | Identifiant |
| --- | --- |
| Utilisateur | `user@roadpass.test` |
| Agent | `agent@roadpass.test` |
| Administrateur | `admin@roadpass.test` |

Les comptes professionnels passent uniquement par « Accès professionnel ». Une inscription publique crée toujours un compte `user`.

## Supabase

Le schéma des profils se trouve dans `supabase/migrations/20260915_profiles.sql`.
La création d’un agent passe par `supabase/functions/create-agent` : la clé
secrète Supabase reste côté serveur et n’est jamais intégrée à Flutter.

Après avoir installé le CLI Supabase et lié le projet :

```bash
npx supabase@latest login
npx supabase@latest link --project-ref <project-ref>
npx supabase@latest db push
npx supabase@latest functions deploy create-agent
```

Le compte administrateur initial doit être créé dans Supabase, puis son profil
doit recevoir `role = 'admin'` dans la table `profiles`. Les créations
d’agents suivantes se font depuis la section « Agents » du dashboard admin.

## Organisation

- `core/` : thème, constantes, routage et composants transverses.
- `models/` : modèles et rôles simples.
- `services/` : contrats et implémentations locales remplaçables.
- `features/` : écrans regroupés par rôle ou parcours.

Sans `--dart-define`, l’application utilise le service mock en mémoire. Avec les
variables Supabase, elle utilise l’authentification réelle et les profils
Postgres. Aucun paiement, calcul de péage, itinéraire ou QR définitif n’est
encore implémenté.
