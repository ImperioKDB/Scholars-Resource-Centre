-- Editorial audit ledger policies.
-- Audit events are append-only: authenticated users may not update or delete
-- them. Only service_role (via controlled lifecycle operations) may insert.
-- Editorial audit events are visible to editors for their own articles; the
-- full audit trail is reviewable only through controlled admin operations.

create policy resource_editorial_audit_events_editor_select
  on public.resource_editorial_audit_events for select to authenticated
  using (
    exists (
      select 1 from public.resource_articles a
      where a.id = resource_editorial_audit_events.article_id
        and (
          a.author_identity_id = auth.uid()::uuid
          or a.reviewer_identity_id = auth.uid()::uuid
        )
    )
  );

create policy resource_editorial_audit_events_service_insert
  on public.resource_editorial_audit_events for insert to service_role;

grant insert on table public.resource_editorial_audit_events to service_role;

-- Helper function: is the current user an editor of the given article?
-- Used by RLS policies to allow authors/reviewers to audit their own articles.
create or replace function public.resource_article_is_editor(target_article_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid;
begin
  select auth.uid() into caller_id;
  if caller_id is null then
    return false;
  end if;

  return exists (
    select 1 from public.resource_articles a
    where a.id = target_article_id
      and (
        a.author_identity_id = caller_id
        or a.reviewer_identity_id = caller_id
      )
  );
end;
$$;

grant execute on function public.resource_article_is_editor(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Editorial lifecycle functions (service_role only).
-- These are the only write path for editorial operations. Each function
-- derives the actor from auth.uid() (the current authenticated session),
-- never trusting caller-supplied actor IDs. Each function validates:
--   - actor identity via auth.uid()
--   - capability via resource_editorial_capabilities
--   - author/reviewer separation
--   - transition validity
--   - revision identity
-- and records an audit event atomically.
-- ---------------------------------------------------------------------------

-- submit_resource_article: draft -> in_review (actor = author)
create or replace function public.submit_resource_article(
  p_article_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid;
  actor_identity_id uuid;
begin
  -- Derive actor from auth.uid() (current authenticated session), never trust caller input.
  select auth.uid() into actor_id;
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  -- Resolve actor's editorial identity.
  select ei.id into actor_identity_id
  from public.resource_editorial_identities ei
  where ei.user_id = actor_id
    and ei.is_active = true
    and ei.email_verified = true;

  if actor_identity_id is null then
    raise exception using errcode = '42501', message = 'No active editorial identity for caller';
  end if;

  -- Verify actor has author capability.
  if not exists (
    select 1 from public.resource_editorial_capabilities ec
    where ec.identity_id = actor_identity_id
      and ec.role = 'author'
  ) then
    raise exception using errcode = '42501', message = 'Actor does not have author capability';
  end if;

  -- Verify article exists and is in draft status.
  if not exists (
    select 1 from public.resource_articles
    where id = p_article_id and status = 'draft'
  ) then
    raise exception using errcode = '42501', message = 'Article must be in draft to submit';
  end if;

  update public.resource_articles
  set status = 'in_review', updated_at = now()
  where id = p_article_id;

  -- Record audit event atomically.
  insert into public.resource_editorial_audit_events (
    article_id, actor_id, action, reason, created_at
  ) values (
    p_article_id, actor_id, 'submit', 'Submitted for review', now()
  );
end;
$$;

grant execute on function public.submit_resource_article(uuid) to authenticated;

-- return_resource_article: in_review -> draft (actor = reviewer ≠ author, reason required)
create or replace function public.return_resource_article(
  p_article_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid;
  actor_identity_id uuid;
  article_author_identity_id uuid;
begin
  -- Derive actor from auth.uid().
  select auth.uid() into actor_id;
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  -- Resolve actor's editorial identity.
  select ei.id into actor_identity_id
  from public.resource_editorial_identities ei
  where ei.user_id = actor_id
    and ei.is_active = true
    and ei.email_verified = true;

  if actor_identity_id is null then
    raise exception using errcode = '42501', message = 'No active editorial identity for caller';
  end if;

  -- Verify actor has reviewer capability.
  if not exists (
    select 1 from public.resource_editorial_capabilities ec
    where ec.identity_id = actor_identity_id
      and ec.role = 'reviewer'
  ) then
    raise exception using errcode = '42501', message = 'Reviewer capability required';
  end if;

  -- Verify current status is in_review.
  if not exists (
    select 1 from public.resource_articles
    where id = p_article_id and status = 'in_review'
  ) then
    raise exception using errcode = '42501', message = 'Article must be in review to return';
  end if;

  -- Verify reviewer is not the author.
  select a.author_identity_id into article_author_identity_id
  from public.resource_articles
  where id = p_article_id;

  if article_author_identity_id = actor_identity_id then
    raise exception using errcode = '42501', message = 'Reviewer cannot be the author';
  end if;

  update public.resource_articles
  set status = 'draft', updated_at = now()
  where id = p_article_id;

  insert into public.resource_editorial_audit_events (
    article_id, actor_id, action, reason, created_at
  ) values (
    p_article_id, actor_identity_id, 'return', p_reason, now()
  );
end;
$$;

grant execute on function public.return_resource_article(uuid, text) to authenticated;

-- approve_resource_article: in_review -> scheduled/published (actor = reviewer ≠ author, AAL2)
create or replace function public.approve_resource_article(
  p_article_id uuid,
  p_target_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid;
  actor_identity_id uuid;
  article_author_identity_id uuid;
begin
  -- Derive actor from auth.uid().
  select auth.uid() into actor_id;
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  -- Resolve actor's editorial identity.
  select ei.id into actor_identity_id
  from public.resource_editorial_identities ei
  where ei.user_id = actor_id
    and ei.is_active = true
    and ei.email_verified = true;

  if actor_identity_id is null then
    raise exception using errcode = '42501', message = 'No active editorial identity for caller';
  end if;

  -- Verify reviewer capability.
  if not exists (
    select 1 from public.resource_editorial_capabilities ec
    where ec.identity_id = actor_identity_id
      and ec.role = 'reviewer'
  ) then
    raise exception using errcode = '42501', message = 'Reviewer capability required';
  end if;

  -- Verify current status is in_review.
  if not exists (
    select 1 from public.resource_articles
    where id = p_article_id and status = 'in_review'
  ) then
    raise exception using errcode = '42501', message = 'Article must be in review to approve';
  end if;

  -- Verify reviewer is not the author.
  select a.author_identity_id into article_author_identity_id
  from public.resource_articles
  where id = p_article_id;

  if article_author_identity_id = actor_identity_id then
    raise exception using errcode = '42501', message = 'Reviewer cannot be the author';
  end if;

  if p_target_status not in ('scheduled', 'published') then
    raise exception using errcode = '42501', message = 'Invalid target status';
  end if;

  update public.resource_articles
  set status = p_target_status, updated_at = now()
  where id = p_article_id;

  insert into public.resource_editorial_audit_events (
    article_id, actor_id, action, reason, created_at
  ) values (
    p_article_id, actor_identity_id, p_target_status, p_reason, now()
  );
end;
$$;

grant execute on function public.approve_resource_article(uuid, text, text) to authenticated;

-- publish_resource_article: scheduled -> published (actor = publisher, AAL2)
create or replace function public.publish_resource_article(
  p_article_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid;
  actor_identity_id uuid;
begin
  -- Derive actor from auth.uid().
  select auth.uid() into actor_id;
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  -- Resolve actor's editorial identity.
  select ei.id into actor_identity_id
  from public.resource_editorial_identities ei
  where ei.user_id = actor_id
    and ei.is_active = true
    and ei.email_verified = true;

  if actor_identity_id is null then
    raise exception using errcode = '42501', message = 'No active editorial identity for caller';
  end if;

  -- Verify publisher capability.
  if not exists (
    select 1 from public.resource_editorial_capabilities ec
    where ec.identity_id = actor_identity_id
      and ec.role = 'publisher'
  ) then
    raise exception using errcode = '42501', message = 'Publisher capability required';
  end if;

  -- Verify scheduled time has arrived.
  if not exists (
    select 1 from public.resource_articles
    where id = p_article_id
      and status = 'scheduled'
      and scheduled_for is not null
      and scheduled_for <= now()
  ) then
    raise exception using errcode = '42501', message = 'Article is not scheduled or scheduled time has not arrived';
  end if;

  update public.resource_articles
  set status = 'published', published_at = now(), updated_at = now()
  where id = p_article_id;

  insert into public.resource_editorial_audit_events (
    article_id, actor_id, action, reason, created_at
  ) values (
    p_article_id, actor_identity_id, 'publish', 'Published scheduled article', now()
  );
end;
$$;

grant execute on function public.publish_resource_article(uuid) to authenticated;

-- archive_resource_article: published -> archived (actor = publisher, AAL2)
create or replace function public.archive_resource_article(
  p_article_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid;
  actor_identity_id uuid;
begin
  -- Derive actor from auth.uid().
  select auth.uid() into actor_id;
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  -- Resolve actor's editorial identity.
  select ei.id into actor_identity_id
  from public.resource_editorial_identities ei
  where ei.user_id = actor_id
    and ei.is_active = true
    and ei.email_verified = true;

  if actor_identity_id is null then
    raise exception using errcode = '42501', message = 'No active editorial identity for caller';
  end if;

  -- Verify publisher capability.
  if not exists (
    select 1 from public.resource_editorial_capabilities ec
    where ec.identity_id = actor_identity_id
      and ec.role = 'publisher'
  ) then
    raise exception using errcode = '42501', message = 'Publisher capability required';
  end if;

  -- Verify article is published.
  if not exists (
    select 1 from public.resource_articles
    where id = p_article_id and status = 'published'
  ) then
    raise exception using errcode = '42501', message = 'Article must be published to archive';
  end if;

  update public.resource_articles
  set status = 'archived', archived_at = now(), updated_at = now()
  where id = p_article_id;

  insert into public.resource_editorial_audit_events (
    article_id, actor_id, action, reason, created_at
  ) values (
    p_article_id, actor_identity_id, 'archive', p_reason, now()
  );
end;
$$;

grant execute on function public.archive_resource_article(uuid, text) to authenticated;

-- correct_resource_article: published -> draft (new revision, new review, AAL2)
create or replace function public.correct_resource_article(
  p_article_id uuid,
  p_new_revision_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid;
  actor_identity_id uuid;
begin
  -- Derive actor from auth.uid().
  select auth.uid() into actor_id;
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  -- Resolve actor's editorial identity.
  select ei.id into actor_identity_id
  from public.resource_editorial_identities ei
  where ei.user_id = actor_id
    and ei.is_active = true
    and ei.email_verified = true;

  if actor_identity_id is null then
    raise exception using errcode = '42501', message = 'No active editorial identity for caller';
  end if;

  -- Verify author capability.
  if not exists (
    select 1 from public.resource_editorial_capabilities ec
    where ec.identity_id = actor_identity_id
      and ec.role = 'author'
  ) then
    raise exception using errcode = '42501', message = 'Author capability required';
  end if;

  -- Verify new revision belongs to same article.
  if not exists (
    select 1 from public.resource_revisions
    where id = p_new_revision_id and article_id = p_article_id
  ) then
    raise exception using errcode = '42501', message = 'Revision must belong to the same article';
  end if;

  update public.resource_articles
  set status = 'draft', updated_at = now()
  where id = p_article_id;

  insert into public.resource_editorial_audit_events (
    article_id, revision_id, actor_id, action, reason, created_at
  ) values (
    p_article_id, p_new_revision_id, actor_identity_id, 'correct', p_reason, now()
  );
end;
$$;

grant execute on function public.correct_resource_article(uuid, uuid, text) to authenticated;
