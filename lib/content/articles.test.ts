// Public content query tests for the Resource Centre editorial backend.
// These tests run against a local Supabase instance with seed data loaded.

import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { createClient as createSupabaseClient } from '@supabase/supabase-js';
import { PublicContent } from './articles';

const SUPABASE_URL = process.env['SUPABASE_URL'] || 'http://localhost:54321';
const SUPABASE_ANON_KEY = process.env['SUPABASE_ANON_KEY'] || 'test-anon-key';

describe('PublicContent - public read queries', () => {
  let content: PublicContent;

  beforeEach(() => {
    content = new PublicContent(SUPABASE_URL, SUPABASE_ANON_KEY);
  });

  it('getPublishedArticles returns only published articles', async () => {
    const articles = await content.getPublishedArticles();
    for (const article of articles) {
      expect(article.status).toBe('published');
      expect(article.published_at).not.toBeNull();
      expect(new Date(article.published_at!).getTime()).toBeLessThanOrEqual(Date.now());
    }
  });

  it('getPublishedArticle returns null for non-existent slug', async () => {
    const article = await content.getPublishedArticle('non-existent-slug');
    expect(article).toBeNull();
  });

  it('getPublishedArticle returns published article by slug', async () => {
    const articles = await content.getPublishedArticles();
    if (articles.length > 0) {
      const firstSlug = articles[0]?.slug;
      if (!firstSlug) return;
      const article = await content.getPublishedArticle(firstSlug);
      expect(article).not.toBeNull();
      expect(article?.slug).toBe(firstSlug);
    }
  });

  it('getCategories returns only active categories', async () => {
    const categories = await content.getCategories();
    for (const category of categories) {
      expect(category.is_active).toBe(true);
    }
  });

  it('getArticleCategories returns article-category associations', async () => {
    const associations = await content.getArticleCategories();
    expect(Array.isArray(associations)).toBe(true);
  });

  it('does not expose internal fields in public article data', async () => {
    const articles = await content.getPublishedArticles();
    for (const article of articles) {
      // These fields should not be present on the public article type
      expect((article as any).created_by).toBeUndefined();
      expect((article as any).updated_by).toBeUndefined();
      expect((article as any).reviewer_identity_id).toBeUndefined();
      expect((article as any).published_revision_id).toBeUndefined();
    }
  });
});
