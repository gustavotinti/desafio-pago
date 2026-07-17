# Desafio Pago — Challenges & Rewards App

A **Flutter + Firebase** app where users create and vote on challenges, earn
cash rewards, and cash out — built with a clean, feature-first architecture.

## Features

- **Google Sign-In** authentication (Firebase Auth).
- **Challenges** — create challenges, browse the feed, and vote. Voting runs
  through a **callable Cloud Function** that enforces authentication, blocks
  double-voting per user, and increments the tally atomically server-side.
- **Wallet & transactions** — per-user balance with a transaction history.
- **Withdrawals** — users request payouts; **admin panels** review and
  manage users and withdrawal requests.

## Architecture

Feature-first, domain-driven layering — each feature is split into
`domain` (entities + repository interfaces), `application` (use cases),
`infrastructure` (Firebase implementations), and `presentation` (UI):

```
lib/
  core/            Shared services (Firestore) and theming.
  features/
    auth/          Google Sign-In, auth user entity, repositories.
    challenge/     Create / list / vote use cases + Firebase repos.
    finance/       Transactions.
    users/         User repository.
    withdrawals/   Withdrawal flow + admin review.
    admin/         Admin pages (users, withdrawals).
functions/
  index.js         Callable `vote` function (server-authoritative voting).
```

Domain code depends only on abstractions; Firebase lives behind repository
interfaces, so the business rules never import the SDK directly.

## Stack

Flutter (Android · iOS · web) · Firebase Auth · Cloud Firestore · Cloud
Functions (Node.js) · Google Sign-In.

## Running locally

```bash
flutter pub get
flutter run
```

Requires your own Firebase project: add the platform config files
(`google-services.json`, `firebase_options.dart`) and deploy the function:

```bash
cd functions && npm install
firebase deploy --only functions
```

## Note

This is a portfolio project demonstrating Flutter app architecture, Firebase
integration, and server-authoritative logic via Cloud Functions.
