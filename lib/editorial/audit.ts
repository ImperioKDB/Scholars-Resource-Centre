// Editorial audit logging.
//
// Every sensitive editorial action (create, edit, submit, approve, reject,
// schedule, publish, archive, correct) is recorded as an append-only audit
// event. Audit events cannot be modified or deleted by editorial roles; only
// service_role (system jobs) may insert them.

import { createClient as createSupabaseClient } from '@supabase/supabase-js';

export interface AuditEvent {
  id: string;
  article_id: string | null;
  revision_id: string | null;
  actor_id: string | null;
  action: string;
  reason: string | null;
  metadata: any;
  created_at: string;
}

export class EditorialAudit {
  private client: ReturnType<typeof createSupabaseClient>;

  constructor(url: string, serviceRoleKey: string) {
    this.client = createSupabaseClient(url, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
  }

  /**
   * Record an editorial audit event. This is append-only: once inserted,
   * the event cannot be modified or deleted by editorial roles.
   */
  async logEvent(params: {
    articleId: string | null;
    revisionId: string | null;
    actorId: string | null;
    action: string;
    reason: string | null;
    metadata?: any;
  }): Promise<void> {
    const { error } = await this.client
      .from('resource_editorial_audit_events')
      .insert({
        article_id: params.articleId,
        revision_id: params.revisionId,
        actor_id: params.actorId,
        action: params.action,
        reason: params.reason,
        metadata: params.metadata ?? null,
      });

    if (error) {
      throw new Error(`Failed to record audit event: ${error.message}`);
    }
  }

  /**
   * Query audit events for an article (editors may view events for their
   * own articles via RLS; service_role sees all).
   */
  async getEventsForArticle(articleId: string): Promise<AuditEvent[]> {
    const { data, error } = await this.client
      .from('resource_editorial_audit_events')
      .select('*')
      .eq('article_id', articleId)
      .order('created_at', { ascending: false });

    if (error) throw new Error(`Failed to load audit events: ${error.message}`);
    return data ?? [];
  }

  /**
   * Query all audit events (service_role only).
   */
  async getAllEvents(): Promise<AuditEvent[]> {
    const { data, error } = await this.client
      .from('resource_editorial_audit_events')
      .select('*')
      .order('created_at', { ascending: false });

    if (error) throw new Error(`Failed to load audit events: ${error.message}`);
    return data ?? [];
  }
}
