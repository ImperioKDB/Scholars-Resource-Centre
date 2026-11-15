// Editorial audit tests for the Resource Centre editorial backend.
// These tests run against a local Supabase instance with seed data loaded.

import { describe, expect, it, beforeEach } from 'vitest';
import { createClient as createSupabaseClient } from '@supabase/supabase-js';
import { EditorialAudit } from './audit';

const SUPABASE_URL = process.env['SUPABASE_URL'] || 'http://localhost:54321';
const SUPABASE_SERVICE_ROLE_KEY = process.env['SUPABASE_SERVICE_ROLE_KEY'] || 'test-service-role-key';

describe('EditorialAudit - audit event recording', () => {
  let audit: EditorialAudit;

  beforeEach(() => {
    audit = new EditorialAudit(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  });

  it('logEvent records an audit event', async () => {
    await audit.logEvent({
      articleId: '00000000-0000-0000-0000-000000000001',
      revisionId: null,
      actorId: '00000000-0000-0000-0000-000000000001',
      action: 'submit',
      reason: 'Submitted for review',
    });

    const events = await audit.getEventsForArticle('00000000-0000-0000-0000-000000000001');
    expect(events.length).toBeGreaterThan(0);
    const submitEvent = events.find((e) => e.action === 'submit');
    expect(submitEvent).toBeDefined();
    expect(submitEvent?.actor_id).toBe('00000000-0000-0000-0000-000000000001');
    expect(submitEvent?.reason).toBe('Submitted for review');
  });

  it('getEventsForArticle returns empty array for non-existent article', async () => {
    const events = await audit.getEventsForArticle('00000000-0000-0000-0000-000000000999');
    expect(events).toEqual([]);
  });

  it('getAllEvents returns all audit events', async () => {
    const events = await audit.getAllEvents();
    expect(Array.isArray(events)).toBe(true);
  });
});
