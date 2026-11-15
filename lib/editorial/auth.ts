// Editorial authentication boundary.
//
// Editorial authentication is INDEPENDENT of Scholars student authentication
// (profiles table, Supabase Auth student flow). Editorial accounts are managed
// through resource_editorial_identities with an optional link to auth.users.
// This preserves the existing platform administrator authority
// (profiles.is_admin) and does not create a second administrator system that
// conflicts with Scholars' existing platform administrator authority.

import { createClient as createSupabaseClient, PostgrestError } from '@supabase/supabase-js';

export interface EditorialIdentity {
  id: string;
  user_id: string | null;
  display_name: string;
  bio: string | null;
  avatar_path: string | null;
  is_active: boolean;
  email_verified: boolean;
  created_at: string;
  updated_at: string;
}

export interface EditorialCapabilities {
  identity_id: string;
  roles: string[]; // 'author' | 'reviewer' | 'publisher'
}

export class EditorialAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'EditorialAuthError';
  }
}

export class EditorialAuth {
  private client: ReturnType<typeof createSupabaseClient>;

  constructor(url: string, anonKey: string) {
    this.client = createSupabaseClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
  }

  /**
   * Get the current editorial identity from the session.
   * Returns null if no authenticated editorial session exists.
   */
  async getCurrentIdentity(): Promise<EditorialIdentity | null> {
    const { data: { user }, error } = await this.client.auth.getUser();
    if (error || !user) return null;

    const { data: identity, error: identityError } = await this.client
      .from('resource_editorial_identities')
      .select('*')
      .eq('user_id', user.id)
      .eq('is_active', true)
      .eq('email_verified', true)
      .maybeSingle() as { data: EditorialIdentity | null; error: PostgrestError | null };

    if (identityError || !identity) return null;

    return {
      id: identity.id,
      user_id: identity.user_id,
      display_name: identity.display_name,
      bio: identity.bio,
      avatar_path: identity.avatar_path,
      is_active: identity.is_active,
      email_verified: identity.email_verified,
      created_at: identity.created_at,
      updated_at: identity.updated_at,
    };
  }

  /**
   * Get the capabilities (roles) for an editorial identity.
   */
  async getCapabilities(identityId: string): Promise<EditorialCapabilities> {
    const { data, error } = await this.client
      .from('resource_editorial_capabilities')
      .select('role')
      .eq('identity_id', identityId) as { data: { role: string }[] | null; error: PostgrestError | null };

    if (error || !data) return { identity_id: identityId, roles: [] };

    return {
      identity_id: identityId,
      roles: data.map((row) => row.role),
    };
  }

  /**
   * Check if the current session has a given editorial capability.
   */
  async hasCapability(identityId: string, role: string): Promise<boolean> {
    const caps = await this.getCapabilities(identityId);
    return caps.roles.includes(role);
  }
}
