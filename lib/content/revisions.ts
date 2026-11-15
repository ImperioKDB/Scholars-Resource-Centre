// Revision content queries (editorial write path only).
// Public visitors cannot read revisions.

import { createClient as createSupabaseClient } from '@supabase/supabase-js';

export interface Revision {
  id: string;
  article_id: string;
  revision_number: number;
  state: any;
  schema_version: number;
  change_summary: string | null;
  created_by: string | null;
  created_at: string;
}

export class RevisionStore {
  private client: ReturnType<typeof createSupabaseClient>;

  constructor(url: string, serviceRoleKey: string) {
    this.client = createSupabaseClient(url, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
  }

  async getRevisionsForArticle(articleId: string): Promise<Revision[]> {
    const { data, error } = await this.client
      .from('resource_revisions')
      .select('*')
      .eq('article_id', articleId)
      .order('revision_number', { ascending: false });

    if (error) throw new Error(`Failed to load revisions: ${error.message}`);
    return data ?? [];
  }

  async createRevision(params: {
    articleId: string;
    revisionNumber: number;
    state: any;
    changeSummary: string | null;
    createdBy: string | null;
  }): Promise<Revision> {
    const { data, error } = await this.client
      .from('resource_revisions')
      .insert({
        article_id: params.articleId,
        revision_number: params.revisionNumber,
        state: params.state,
        change_summary: params.changeSummary,
        created_by: params.createdBy,
      })
      .select()
      .single();

    if (error) throw new Error(`Failed to create revision: ${error.message}`);
    return data;
  }
}
