// Category content queries (public read path).

import { createClient as createSupabaseClient } from '@supabase/supabase-js';
import type { PublicCategory, PublicArticleCategory } from './articles';

export class PublicCategories {
  private client: ReturnType<typeof createSupabaseClient>;

  constructor(url: string, anonKey: string) {
    this.client = createSupabaseClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
  }

  async getActiveCategories(): Promise<PublicCategory[]> {
    const { data, error } = await this.client
      .from('resource_public_categories')
      .select('*')
      .order('display_order', { ascending: true });

    if (error) throw new Error(`Failed to load categories: ${error.message}`);
    return data ?? [];
  }

  async getArticleCategories(): Promise<PublicArticleCategory[]> {
    const { data, error } = await this.client
      .from('resource_public_article_categories')
      .select('*');

    if (error) throw new Error(`Failed to load article categories: ${error.message}`);
    return data ?? [];
  }
}
