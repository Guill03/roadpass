# RoadPass

Socle Flutter multi-plateforme pour une future plateforme de gestion des passages aux postes de péage.

## Lancer le projet

Sans configuration Supabase, l’application utilise l’authentification mock en
mémoire. Si `.env` contient `SUPABASE_URL` et `SUPABASE_PUBLISHABLE_KEY`, le
mode Supabase est sélectionné automatiquement.

```bash
flutter pub get
flutter run -d chrome
# ou : flutter run -d windows
```

La configuration locale est chargée depuis `.env` (fichier ignoré par Git et
inclus comme asset Flutter). Exemple de noms de variables, avec des valeurs
propres au projet :

```dotenv
ROADPASS_AUTH_MODE=supabase
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

`ROADPASS_AUTH_MODE=mock` force le mock même si les deux valeurs Supabase sont
présentes. `--dart-define=ROADPASS_AUTH_MODE=...` a priorité sur `.env`. Le mode
Supabase échoue au démarrage si l’URL ou la clé publishable manque. La clé
publishable est une configuration client, pas un secret : les autorisations
doivent rester appliquées par RLS et côté serveur.

Vérification :

```bash
flutter analyze
flutter test
```

## Comptes de démonstration

En mode mock uniquement, les comptes suivants utilisent le mot de passe
`RoadPass123!`.

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

Le mode mock est isolé en mémoire et n’appelle pas Supabase. En mode Supabase,
l’authentification et les profils utilisent le backend configuré. Aucun
paiement, calcul d’itinéraire ou parcours QR définitif n’est encore implémenté.
