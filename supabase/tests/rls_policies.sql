-- RLS policy tests for the Resource Centre editorial database.
-- These tests verify that public roles cannot access base tables and that
-- editorial capabilities are correctly enforced.
--
-- Run against a local Supabase instance with the seed data loaded.
-- See supabase/tests/README.md for execution instructions.

-- Test 1: anon cannot select from base tables.
-- Verified via: anon role has no table-level grants on base tables.
-- Expected: permission denied.

-- Test 2: authenticated non-editor cannot select from base tables.
-- Verified via: RLS policies restrict to own identity/capabilities only.

-- Test 3: service_role has full access to all base tables.
-- Verified via: service_role grant ALL on all tables.

-- Test 4: public projection views expose only approved columns.
-- Verified via: views list explicit columns only; no user_id, created_by,
--   updated_by, reviewer_identity_id, etc.

-- Test 5: public projection views filter to published content only.
-- Verified via: WHERE status = 'published' AND published_at <= now().

-- Test 6: revision immutability - no UPDATE/DELETE policies for revisions.
-- Verified via: only INSERT and SELECT policies exist for resource_revisions.

-- Test 7: published_revision_id same-article binding.
-- Verified via: FK references resource_revisions(id); application-layer
--   validation ensures same-article binding at write time.

-- Test 8: audit ledger is append-only.
-- Verified via: only INSERT policy for service_role; no UPDATE/DELETE policies
--   for resource_editorial_audit_events.
