-- Editorial capability policies and helper.
-- Editorial capabilities link editorial identities to author/reviewer/publisher roles.
-- Only service_role (system jobs) may write; authenticated users may read their own
-- capabilities via the helper function. Platform admin authority (profiles.is_admin)
-- is NOT used here; editorial capabilities are granted through an independent
-- editorial lifecycle.

create policy resource_editorial_capabilities_identity_select
  on public.resource_editorial_capabilities for select to authenticated
  using (public.resource_identity_is_owner(identity_id));

create policy resource_editorial_capabilities_service_all
  on public.resource_editorial_capabilities for all to service_role;

-- Grant select on base table to authenticated so the helper function can read it
-- under RLS.
grant select on table public.resource_editorial_capabilities to authenticated;

-- Helper function: is the current authenticated user the owner of the given
-- editorial identity? Used by RLS policies to allow identity owners to read their
-- own capabilities without exposing all identities.
create or replace function public.resource_identity_is_owner(target_identity_id uuid)
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

  -- An authenticated user may read their own capabilities. We look up the
  -- editorial identity linked to their auth.users id.
  return exists (
    select 1 from public.resource_editorial_identities ei
    where ei.id = target_identity_id
      and ei.user_id = caller_id
      and ei.is_active = true
  );
end;
$$;

grant execute on function public.resource_identity_is_owner(uuid) to authenticated;
