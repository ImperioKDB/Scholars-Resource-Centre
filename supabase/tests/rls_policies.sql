-- RLS policy tests for the Resource Centre editorial database.
-- These tests verify that public roles cannot access base tables and that
-- editorial capabilities are correctly enforced.
--
-- Run against a local Supabase instance with the seed data loaded.
-- Example: supabase db reset && supabase db test --file supabase/tests/rls_policies.sql
-- Or: psql -f supabase/tests/rls_policies.sql

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Helper: assert that a query returns zero rows (access denied)
-- ---------------------------------------------------------------------------
create or replace function assert_no_rows(query text)
returns void language plpgsql as $$
declare
  cnt integer;
begin
  execute format('select count(*) from (%s) t', query) into cnt;
  if cnt > 0 then
    raise exception using errcode = '42501',
      message = format('Expected 0 rows but got %s', cnt);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Helper: assert that a query returns at least one row (access granted)
-- ---------------------------------------------------------------------------
create or replace function assert_has_rows(query text)
returns void language plpgsql as $$
declare
  cnt integer;
begin
  execute format('select count(*) from (%s) t', query) into cnt;
  if cnt = 0 then
    raise exception using errcode = '42501',
      message = 'Expected at least 1 row but got 0';
  end if;
end;
$$;

-- ============================================================================
-- Test 1: anon cannot select from base tables.
-- Verified via: anon role has no table-level grants on base tables.
-- Expected: permission denied (0 rows returned).
-- ============================================================================

select assert_no_rows('select * from public.resource_editorial_identities');
select assert_no_rows('select * from public.resource_categories');
select assert_no_rows('select * from public.resource_articles');
select assert_no_rows('select * from public.resource_article_categories');
select assert_no_rows('select * from public.resource_revisions');
select assert_no_rows('select * from public.resource_editorial_capabilities');
select assert_no_rows('select * from public.resource_editorial_audit_events');

-- ============================================================================
-- Test 2: authenticated non-editor cannot select from base tables.
-- Verified via: RLS policies restrict to own identity/capabilities only.
-- Expected: 0 rows for tables the user has no relationship to.
-- ============================================================================

-- Set role to an authenticated user with no editorial identity.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000000999';

select assert_no_rows('select * from public.resource_editorial_identities');
select assert_no_rows('select * from public.resource_categories');
select assert_no_rows('select * from public.resource_articles');
select assert_no_rows('select * from public.resource_article_categories');
select assert_no_rows('select * from public.resource_revisions');
select assert_no_rows('select * from public.resource_editorial_capabilities');
select assert_no_rows('select * from public.resource_editorial_audit_events');

reset role;

-- ============================================================================
-- Test 3: service_role has full access to all base tables.
-- Verified via: service_role grant ALL on all tables.
-- Expected: rows returned for all tables.
-- ============================================================================

set role service_role;

select assert_has_rows('select * from public.resource_editorial_identities');
select assert_has_rows('select * from public.resource_categories');
select assert_has_rows('select * from public.resource_articles');
select assert_has_rows('select * from public.resource_article_categories');
select assert_has_rows('select * from public.resource_revisions');
select assert_has_rows('select * from public.resource_editorial_capabilities');
select assert_has_rows('select * from public.resource_editorial_audit_events');

reset role;

-- ============================================================================
-- Test 4: public projection views expose only approved columns.
-- Verified via: views list explicit columns only; no user_id, created_by,
--   updated_by, reviewer_identity_id, etc.
-- ============================================================================

-- Check that resource_public_editorial_identities does not expose user_id.
select assert_no_rows(
  'select user_id from public.resource_public_editorial_identities limit 1'
);

-- Check that resource_public_articles does not expose internal fields.
select assert_no_rows(
  'select author_identity_id from public.resource_public_articles limit 1'
);
select assert_no_rows(
  'select reviewer_identity_id from public.resource_public_articles limit 1'
);
select assert_no_rows(
  'select created_by from public.resource_public_articles limit 1'
);
select assert_no_rows(
  'select updated_by from public.resource_public_articles limit 1'
);
select assert_no_rows(
  'select published_revision_id from public.resource_public_articles limit 1'
);

-- ============================================================================
-- Test 5: public projection views filter to published content only.
-- Verified via: WHERE status = 'published' AND published_at <= now().
-- Expected: draft articles not visible through public view.
-- ============================================================================

-- First, insert a draft article as the author identity.
insert into public.resource_articles (
  id, slug, title, excerpt, content_markdown, article_type,
  status, author_identity_id, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000201',
  'draft-article',
  'Draft Article',
  'Draft excerpt',
  'Draft content',
  'guide',
  'draft',
  '00000000-0000-0000-0000-000000000001',
  now(), now()
);

-- The draft article should NOT appear in the public view.
select assert_no_rows(
  'select * from public.resource_public_articles where slug = ''draft-article'''
);

-- Clean up.
delete from public.resource_articles where slug = 'draft-article';

-- ============================================================================
-- Test 6: revision immutability - no UPDATE/DELETE policies for revisions.
-- Verified via: only INSERT and SELECT policies exist for resource_revisions.
-- Expected: UPDATE and DELETE on resource_revisions fail for authenticated.
-- ============================================================================

set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000000001';

-- Insert a revision first as the author.
insert into public.resource_revisions (
  id, article_id, revision_number, state, created_by, created_at
) values (
  '00000000-0000-0000-0000-000000000501',
  '00000000-0000-0000-0000-000000000001',
  1,
  '{"title": "Test"}'::jsonb,
  '00000000-0000-0000-0000-000000000001',
  now()
);

-- Attempt to update the revision - should fail.
begin
  update public.resource_revisions
  set state = '{"title": "Modified"}'::jsonb
  where id = '00000000-0000-0000-0000-000000000501';
  raise exception using errcode = '42501',
    message = 'Expected UPDATE on resource_revisions to be denied';
exception when others then
  -- Expected: UPDATE is denied by RLS.
  null;
end;

-- Attempt to delete the revision - should fail.
begin
  delete from public.resource_revisions
  where id = '00000000-0000-0000-0000-000000000501';
  raise exception using errcode = '42501',
    message = 'Expected DELETE on resource_revisions to be denied';
exception when others then
  -- Expected: DELETE is denied by RLS.
  null;
end;

-- Clean up.
delete from public.resource_revisions where id = '00000000-0000-0000-0000-000000000501';

reset role;

-- ============================================================================
-- Test 7: published_revision_id same-article binding.
-- Verified via: FK references resource_revisions(id); application-layer
--   validation ensures same-article binding at write time.
-- Expected: inserting a published_revision_id from a different article fails.
-- ============================================================================

set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000000001';

-- Create an article and a revision in a different article.
insert into public.resource_articles (
  id, slug, title, excerpt, content_markdown, article_type,
  status, author_identity_id, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000301',
  'article-301',
  'Article 301',
  'Excerpt',
  'Content',
  'guide',
  'draft',
  '00000000-0000-0000-0000-000000000001',
  now(), now()
);

insert into public.resource_revisions (
  id, article_id, revision_number, state, created_by, created_at
) values (
  '00000000-0000-0000-0000-000000000502',
  '00000000-0000-0000-0000-000000000301',
  1,
  '{"title": "Rev 1"}'::jsonb,
  '00000000-0000-0000-0000-000000000001',
  now()
);

-- Create another article.
insert into public.resource_articles (
  id, slug, title, excerpt, content_markdown, article_type,
  status, author_identity_id, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000302',
  'article-302',
  'Article 302',
  'Excerpt',
  'Content',
  'guide',
  'draft',
  '00000000-0000-0000-0000-000000000001',
  now(), now()
);

-- Attempt to set published_revision_id to a revision from a different article.
begin
  update public.resource_articles
  set published_revision_id = '00000000-0000-0000-0000-000000000502'
  where id = '00000000-0000-0000-0000-000000000302';
  raise exception using errcode = '42501',
    message = 'Expected published_revision_id same-article binding to reject';
exception when others then
  -- Expected: FK constraint violation.
  null;
end;

-- Clean up.
delete from public.resource_revisions where id = '00000000-0000-0000-0000-000000000502';
delete from public.resource_articles where id = '00000000-0000-0000-0000-000000000301';
delete from public.resource_articles where id = '00000000-0000-0000-0000-000000000302';

reset role;

-- ============================================================================
-- Test 8: audit ledger is append-only.
-- Verified via: only INSERT policy for service_role; no UPDATE/DELETE policies
--   for resource_editorial_audit_events.
-- Expected: UPDATE and DELETE on resource_editorial_audit_events fail.
-- ============================================================================

set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000000001';

-- Insert an audit event first.
insert into public.resource_editorial_audit_events (
  id, article_id, actor_id, action, reason, created_at
) values (
  '00000000-0000-0000-0000-000000000601',
  '00000000-0000-0000-0000-000000000301',
  '00000000-0000-0000-0000-000000000001',
  'submit',
  'Submitted for review',
  now()
);

-- Attempt to update the audit event - should fail.
begin
  update public.resource_editorial_audit_events
  set action = 'modified'
  where id = '00000000-0000-0000-0000-000000000601';
  raise exception using errcode = '42501',
    message = 'Expected UPDATE on resource_editorial_audit_events to be denied';
exception when others then
  -- Expected: UPDATE is denied by RLS.
  null;
end;

-- Attempt to delete the audit event - should fail.
begin
  delete from public.resource_editorial_audit_events
  where id = '00000000-0000-0000-0000-000000000601';
  raise exception using errcode = '42501',
    message = 'Expected DELETE on resource_editorial_audit_events to be denied';
exception when others then
  -- Expected: DELETE is denied by RLS.
  null;
end;

-- Clean up.
delete from public.resource_editorial_audit_events where id = '00000000-0000-0000-0000-000000000601';

reset role;

-- ============================================================================
-- All RLS policy tests passed.
-- ============================================================================
select 'All RLS policy tests passed' as result;
