# Scholars Resource Centre — Backend

Independent editorial backend for the Scholars Resource Centre.

## Purpose

This repository hosts the **backend-only** infrastructure for the Scholars
Resource Centre editorial publishing system. It is intentionally separate from
the Scholars frontend application (`ImperioKDB/Scholars`), which continues to
serve the public Resource Centre pages at `/resources`.

The public frontend remains in `ImperioKDB/Scholars` and reads published
content through this backend's public projection views. Editorial operations
(authoring, review, scheduling, publishing, archiving, correction) live here
and are protected by an independent editorial authorization model.

## Architecture

- **Public read model:** Dedicated projection views expose only approved,
  published articles and categories to unauthenticated readers. No base-table
  access is granted to public roles.
- **Editorial authorization:** Separate from Scholars student authentication
  and from Scholars platform administrator (`profiles.is_admin`) authority.
  Editorial capabilities (author, reviewer, publisher) are granted through an
  editorial capability model, not through platform admin status.
- **Revision integrity:** Immutable revision snapshots with same-article
  binding; corrections create new revisions, never mutate history.
- **Audit ledger:** Append-only editorial audit events record who did what,
  when, and why for every sensitive editorial action.

## Repository structure

```
supabase/
  config.toml              # Supabase project configuration
  migrations/              # Version-controlled SQL migrations
  tests/                   # Database and security tests
lib/
  editorial/               # Editorial authentication, authorization, audit
  content/                 # Content queries (articles, categories, revisions)
  storage/                 # Image storage access
reports/scholars/docs/     # Migration map and cross-repo documentation
```

## Getting started

```bash
cp .env.example .env.local
# Fill in Supabase project credentials (public URL + anon key only;
# service-role key is server-only and never committed)
npm install
npx supabase start        # local development
npx supabase db reset     # apply migrations to local database
npm run test              # run test suite
```

## Security boundaries

- Service-role credentials are **server-only** and never exposed to the
  frontend.
- Public roles (`anon`, `authenticated`) have no direct base-table access;
  they read only through explicit column-projection views.
- Editorial authorization is independent of Scholars platform administrator
  authority (`profiles.id_admin`). No shared admin system.
- All storage assets are served through approved path prefixes only.
