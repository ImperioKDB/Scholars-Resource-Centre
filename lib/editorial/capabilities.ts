// Editorial capability boundaries.
//
// Defines what each editorial role may do. These are business-logic checks
// applied by server-side code before any database mutation. They are NOT tied
// to Scholars platform administrator authority (profiles.is_admin).

export type EditorialRole = 'author' | 'reviewer' | 'publisher';

export interface CapabilityCheck {
  actorId: string;
  actorRole: EditorialRole;
  targetId: string;
  action: string;
}

export class EditorialCapabilities {
  /** An author may create and edit drafts, and submit for review. */
  static canCreateDraft(actorRole: EditorialRole): boolean {
    return actorRole === 'author' || actorRole === 'publisher';
  }

  /** An author may edit their own draft. */
  static canEditDraft(actorRole: EditorialRole, isOwnDraft: boolean): boolean {
    if (!isOwnDraft) return false;
    return actorRole === 'author' || actorRole === 'publisher';
  }

  /** An author may submit their own draft for review. */
  static canSubmitForReview(actorRole: EditorialRole, isOwnDraft: boolean): boolean {
    if (!isOwnDraft) return false;
    return actorRole === 'author' || actorRole === 'publisher';
  }

  /** A reviewer may review and approve/reject articles, but must not be the
   * author of the article they review. */
  static canReview(actorRole: EditorialRole, isAuthor: boolean): boolean {
    if (isAuthor) return false; // reviewer ≠ author
    return actorRole === 'reviewer' || actorRole === 'publisher';
  }

  /** A publisher may schedule articles. */
  static canSchedule(actorRole: EditorialRole): boolean {
    return actorRole === 'publisher';
  }

  /** A publisher may publish articles. */
  static canPublish(actorRole: EditorialRole): boolean {
    return actorRole === 'publisher';
  }

  /** A publisher may archive articles. */
  static canArchive(actorRole: EditorialRole): boolean {
    return actorRole === 'publisher';
  }

  /** An author may correct (revert to draft) their own published article,
   * creating a new revision requiring new review. */
  static canCorrect(actorRole: EditorialRole, isAuthor: boolean): boolean {
    if (!isAuthor) return false;
    return actorRole === 'author' || actorRole === 'publisher';
  }

  /** Validate a complete editorial action request. */
  static validate(params: CapabilityCheck): { allowed: boolean; reason?: string } {
    const { actorRole, action } = params;

    switch (action) {
      case 'create_draft':
        if (!this.canCreateDraft(actorRole)) {
          return { allowed: false, reason: 'Insufficient capability to create draft' };
        }
        return { allowed: true };

      case 'edit_draft':
        if (!this.canEditDraft(actorRole, true)) {
          return { allowed: false, reason: 'Cannot edit another user\'s draft' };
        }
        return { allowed: true };

      case 'submit_for_review':
        if (!this.canSubmitForReview(actorRole, true)) {
          return { allowed: false, reason: 'Cannot submit another user\'s draft' };
        }
        return { allowed: true };

      case 'review':
        // Reviewer identity is checked separately against article author
        if (!this.canReview(actorRole, false)) {
          return { allowed: false, reason: 'Reviewer cannot be the author' };
        }
        return { allowed: true };

      case 'schedule':
        if (!this.canSchedule(actorRole)) {
          return { allowed: false, reason: 'Insufficient capability to schedule' };
        }
        return { allowed: true };

      case 'publish':
        if (!this.canPublish(actorRole)) {
          return { allowed: false, reason: 'Insufficient capability to publish' };
        }
        return { allowed: true };

      case 'archive':
        if (!this.canArchive(actorRole)) {
          return { allowed: false, reason: 'Insufficient capability to archive' };
        }
        return { allowed: true };

      case 'correct':
        if (!this.canCorrect(actorRole, true)) {
          return { allowed: false, reason: 'Cannot correct another user\'s article' };
        }
        return { allowed: true };

      default:
        return { allowed: false, reason: `Unknown action: ${action}` };
    }
  }
}
