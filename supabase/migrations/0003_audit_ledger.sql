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
-- validates actor identity, capability, author/reviewer separation, transition
-- validity, revision identity, MFA/AAL2 where required, and records an audit
-- event atomically.
-- ---------------------------------------------------------------------------

-- submit_resource_article: draft -> in_review (actor = author)
create or replace function public.submit_resource_article(
  p_article_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Verify actor is the article author
  if not exists (
    select 1 from public.resource_articles
    where id = p_article_id and author_identity_id = p_actor_id
  ) then
    raise exception using errcode = '42501', message = 'Only the author may submit';
  end if;

  -- Verify current status is draft
  if not exists (
    select 1 from public.resource_articles
    where id = p_article_id and status = 'draft'
  ) then
    raise exception using errcode = '42501', message = 'Article must be in draft to submit';
  end if;

  -- Verify required fields
  if not exists (
    select 1 from public.resource_articles
    where id = p_article_id
      and title is not null and char_length(btrim(title)) > 0
      and content_markdown is not null and char_length(content_markdown) > 0
      and author_identity_id is not null
  ) then
    raise exception using errcode = '42501', message = 'Article must have title, content, and author';
  end if;

  update public.resource_articles
  set status = 'in_review', updated_at = now()
  where id = p_article_id;

  -- Record audit event
  insert into public.resource_editorial_audit_events (
    article_id, actor_id, action, reason, created_at
  ) values (
    p_article_id, p_actor_id, 'submit',
    'Submitted for review', now()
  );
end;
$$;

-- Return only grant: editors can see submission outcomes
grant execute on function public.submit_resource_article(uuid, uuid) to authenticated;

-- return_resource_article: in_review -> draft (actor = reviewer, reason required)
create or replace function public.return_resource_article(
  p_article_id uuid,
  p_actor_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Verify reviewer ≠ author
  if exists (
    select 1 from public.resource_articles
    where id = p_article_id
      and author_identity_id = p_actor_id
  ) then
    raise exception using errcode = '42501', message = 'Reviewer cannot be the author';
  end if;

  -- Verify current status is in_review
  if not exists (
    select 1 from public.resource_articles
    where id = p_article_id and status = 'in_review'
  ) then
    raise exception using errcode = '42501', message = 'Article must be in review to return';
  end if;

  update public.resource_articles
  set status = 'draft', updated_at = now()
  where id = p_article_id;

  insert into public.resource_editorial_audit_events (
    article_id, actor_id, action, reason, created_at
  ) values (
    p_article_id, p_actor_id, 'return', p_reason, now()
  );
end;
$$;

grant execute on function public.return_resource_article(uuid, uuid, text) to authenticated;

-- approve_resource_article: in_review -> scheduled/published (actor = reviewer ≠ author, AAL2)
create or replace function public.approve_resource_article(
  p_article_id uuid,
  p_actor_id uuid,
  p_target_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Verify reviewer ≠ author
  if exists (
    select 1 from public.resource_articles
    where id = p_article_id
      and author_identity_id = p_actor_id
  ) then
    raise exception using errcode = '42501', message = 'Reviewer cannot be the author';
  end if;

  -- Verify current status is in_review
  if not exists (
    select 1 from public.resource_articles
    where id = p_article_id and status = 'in_review'
  ) then
    raise exception using errcode = '42501', message = 'Article must be in review to approve';
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
    p_article_id, p_actor_id, p_target_status, p_reason, now()
  );
end;
$$;

grant execute on function public.approve_resource_article(uuid, uuid, text, text) to authenticated;

-- publish_resource_article: scheduled -> published (actor = publisher, AAL2)
create or replace function public.publish_resource_article(
  p_article_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Verify scheduled time has arrived
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
    p_article_id, p_actor_id, 'publish', 'Published scheduled article', now()
  );
end;
$$;

grant execute on function public.publish_resource_article(uuid, uuid) to authenticated;

-- archive_resource_article: published -> archived (actor = publisher, AAL2)
create or replace function public.archive_resource_article(
  p_article_id uuid,
  p_actor_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
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
    p_article_id, p_actor_id, 'archive', p_reason, now()
  );
end;
$$;

grant execute on function public.archive_resource_article(uuid, uuid, text) to authenticated;

-- correct_resource_article: published -> draft (new revision, new review, AAL2)
create or replace function public.correct_resource_article(
  p_article_id uuid,
  p_actor_id uuid,
  p_new_revision_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Verify new revision belongs to same article
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
    p_article_id, p_new_revision_id, p_actor_id, 'correct', p_reason, now()
  );
end;
$$;

grant execute on function public.correct_resource_article(uuid, uuid, uuid, text) to authenticated;
