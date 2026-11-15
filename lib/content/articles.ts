// Content queries for the Resource Centre.
//
// Public reads use projection views (read-only, column-projected).
// Editorial writes go through guarded server-side functions.

import { createClient as createSupabaseClient } from '@supabase/supabase-js';

export interface PublicArticle {
  id: string;
  slug: string;
  title: string;
  excerpt: string | null;
  content_markdown: string;
  article_type: string;
  canonical_url: string | null;
  featured_image_path: string | null;
  reading_time_minutes: number | null;
  published_at: string;
  last_reviewed_at: string | null;
  author_name: string;
  author_bio: string | null;
  author_avatar_path: string | null;
}

export interface PublicCategory {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  display_order: number;
}

export interface PublicArticleCategory {
  article_id: string;
  category_id: string;
  slug: string;
  name: string;
  description: string | null;
  display_order: number;
}

export class PublicContent {
  private client: ReturnType<typeof createSupabaseClient>;

  constructor(url: string, anonKey: string) {
    this.client = createSupabaseClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
  }

  /** Get all published articles. Public read path - no authentication required. */
  async getPublishedArticles(): Promise<PublicArticle[]> {
    const { data, error } = await this.client
      .from('resource_public_articles')
      .select('*')
      .order('published_at', { ascending: false });

    if (error) throw new Error(`Failed to load published articles: ${error.message}`);
    return data ?? [];
  }

  /** Get a single published article by slug. */
  async getPublishedArticle(slug: string): Promise<PublicArticle | null> {
    const { data, error } = await this.client
      .from('resource_public_articles')
      .select('*')
      .eq('slug', slug)
      .maybeSingle();

    if (error) throw new Error(`Failed to load article: ${error.message}`);
    return data ?? null;
  }

  /** Get all active categories. */
  async getCategories(): Promise<PublicCategory[]> {
    const { data, error } = await this.client
      .from('resource_public_categories')
      .select('*')
      .order('display_order', { ascending: true });

    if (error) throw new Error(`Failed to load categories: ${error.message}`);
    return data ?? [];
  }

  /** Get article-category associations for published content. */
  async getArticleCategories(): Promise<PublicArticleCategory[]> {
    const { data, error } = await this.client
      .from('resource_public_article_categories')
      .select('*');

    if (error) throw new Error(`Failed to load article categories: ${error.message}`);
    return data ?? [];
  }
}
