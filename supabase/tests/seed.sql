-- Seed data for local development and testing.
-- Uses synthetic identities only; no production user data.

-- Insert synthetic editorial identities for testing.
insert into public.resource_editorial_identities (
  id, email, display_name, bio, is_active, email_verified
) values
  (
    '00000000-0000-0000-0000-000000000001',
    'author@example.scholars',
    'Test Author',
    'Test author for development.',
    true,
    true
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    'reviewer@example.scholars',
    'Test Reviewer',
    'Test reviewer for development.',
    true,
    true
  ),
  (
    '00000000-0000-0000-0000-000000000003',
    'publisher@example.scholars',
    'Test Publisher',
    'Test publisher for development.',
    true,
    true
  ),
  (
    '00000000-0000-0000-0000-000000000004',
    'inactive@example.scholars',
    'Inactive Identity',
    'Inactive identity for testing.',
    false,
    true
  )
on conflict (email) do nothing;

-- Insert synthetic categories.
insert into public.resource_categories (
  id, slug, name, description, display_order, is_active
) values
  (
    '00000000-0000-0000-0000-000000000101',
    'scholarship-applications',
    'Scholarship applications',
    'Practical guidance for finding opportunities.',
    1,
    true
  ),
  (
    '00000000-0000-0000-0000-000000000102',
    'essays-and-letters',
    'Essays and letters',
    'Writing guides for applications.',
    2,
    true
  ),
  (
    '00000000-0000-0000-0000-000000000103',
    'scam-awareness',
    'Scam awareness',
    'Verification and safety information.',
    3,
    true
  )
on conflict (slug) do nothing;

-- Grant editorial capabilities to synthetic identities.
insert into public.resource_editorial_capabilities (identity_id, role) values
  ('00000000-0000-0000-0000-000000000001', 'author'),
  ('00000000-0000-0000-0000-000000000002', 'reviewer'),
  ('00000000-0000-0000-0000-000000000003', 'publisher')
on conflict (identity_id, role) do nothing;
