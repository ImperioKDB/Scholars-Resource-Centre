// Public category query tests for the Resource Centre editorial backend.
// These tests run against a local Supabase instance with seed data loaded.

import { describe, expect, it, beforeEach } from 'vitest';
import { createClient as createSupabaseClient } from '@supabase/supabase-js';
import { PublicCategories } from './categories';

const SUPABASE_URL = process.env['SUPABASE_URL'] || 'http://localhost:54321';
const SUPABASE_ANON_KEY = process.env['SUPABASE_ANON_KEY'] || 'test-anon-key';

describe('PublicCategories - public category queries', () => {
  let categories: PublicCategories;

  beforeEach(() => {
    categories = new PublicCategories(SUPABASE_URL, SUPABASE_ANON_KEY);
  });

  it('getActiveCategories returns only active categories', async () => {
    const result = await categories.getActiveCategories();
    for (const category of result) {
      expect(category.is_active).toBe(true);
    }
  });

  it('getArticleCategories returns article-category associations', async () => {
    const associations = await categories.getArticleCategories();
    expect(Array.isArray(associations)).toBe(true);
  });
});
