// Editorial authentication tests for the Resource Centre editorial backend.
// These tests run against a local Supabase instance with seed data loaded.

import { describe, expect, it, beforeEach } from 'vitest';
import { createClient as createSupabaseClient } from '@supabase/supabase-js';
import { EditorialAuth } from './auth';

const SUPABASE_URL = process.env['SUPABASE_URL'] || 'http://localhost:54321';
const SUPABASE_ANON_KEY = process.env['SUPABASE_ANON_KEY'] || 'test-anon-key';

describe('EditorialAuth - editorial authentication', () => {
  let auth: EditorialAuth;

  beforeEach(() => {
    auth = new EditorialAuth(SUPABASE_URL, SUPABASE_ANON_KEY);
  });

  it('getCurrentIdentity returns null for unauthenticated session', async () => {
    const identity = await auth.getCurrentIdentity();
    expect(identity).toBeNull();
  });

  it('getCapabilities returns empty roles for non-existent identity', async () => {
    const caps = await auth.getCapabilities('00000000-0000-0000-0000-000000000999');
    expect(caps.identity_id).toBe('00000000-0000-0000-0000-000000000999');
    expect(caps.roles).toEqual([]);
  });

  it('hasCapability returns false for non-existent identity', async () => {
    const hasCap = await auth.hasCapability(
      '00000000-0000-0000-0000-000000000999',
      'author'
    );
    expect(hasCap).toBe(false);
  });
});
