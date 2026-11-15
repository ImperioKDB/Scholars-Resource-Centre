// Editorial capability tests for the Resource Centre editorial backend.
// These tests verify the capability boundary logic without requiring a database.

import { describe, expect, it } from 'vitest';
import { EditorialCapabilities } from './capabilities';

describe('EditorialCapabilities - capability checks', () => {
  describe('canCreateDraft', () => {
    it('allows author', () => {
      expect(EditorialCapabilities.canCreateDraft('author')).toBe(true);
    });
    it('allows publisher', () => {
      expect(EditorialCapabilities.canCreateDraft('publisher')).toBe(true);
    });
    it('denies reviewer', () => {
      expect(EditorialCapabilities.canCreateDraft('reviewer')).toBe(false);
    });
  });

  describe('canEditDraft', () => {
    it('allows author on own draft', () => {
      expect(EditorialCapabilities.canEditDraft('author', true)).toBe(true);
    });
    it('denies author on other draft', () => {
      expect(EditorialCapabilities.canEditDraft('author', false)).toBe(false);
    });
    it('allows publisher on own draft', () => {
      expect(EditorialCapabilities.canEditDraft('publisher', true)).toBe(true);
    });
    it('denies reviewer', () => {
      expect(EditorialCapabilities.canEditDraft('reviewer', true)).toBe(false);
    });
  });

  describe('canSubmitForReview', () => {
    it('allows author on own draft', () => {
      expect(EditorialCapabilities.canSubmitForReview('author', true)).toBe(true);
    });
    it('denies author on other draft', () => {
      expect(EditorialCapabilities.canSubmitForReview('author', false)).toBe(false);
    });
    it('allows publisher on own draft', () => {
      expect(EditorialCapabilities.canSubmitForReview('publisher', true)).toBe(true);
    });
    it('denies reviewer', () => {
      expect(EditorialCapabilities.canSubmitForReview('reviewer', true)).toBe(false);
    });
  });

  describe('canReview', () => {
    it('allows reviewer who is not author', () => {
      expect(EditorialCapabilities.canReview('reviewer', false)).toBe(true);
    });
    it('denies reviewer who is author', () => {
      expect(EditorialCapabilities.canReview('reviewer', true)).toBe(false);
    });
    it('allows publisher', () => {
      expect(EditorialCapabilities.canReview('publisher', false)).toBe(true);
    });
    it('denies author', () => {
      expect(EditorialCapabilities.canReview('author', false)).toBe(false);
    });
  });

  describe('canSchedule', () => {
    it('allows publisher', () => {
      expect(EditorialCapabilities.canSchedule('publisher')).toBe(true);
    });
    it('denies author', () => {
      expect(EditorialCapabilities.canSchedule('author')).toBe(false);
    });
    it('denies reviewer', () => {
      expect(EditorialCapabilities.canSchedule('reviewer')).toBe(false);
    });
  });

  describe('canPublish', () => {
    it('allows publisher', () => {
      expect(EditorialCapabilities.canPublish('publisher')).toBe(true);
    });
    it('denies author', () => {
      expect(EditorialCapabilities.canPublish('author')).toBe(false);
    });
    it('denies reviewer', () => {
      expect(EditorialCapabilities.canPublish('reviewer')).toBe(false);
    });
  });

  describe('canArchive', () => {
    it('allows publisher', () => {
      expect(EditorialCapabilities.canArchive('publisher')).toBe(true);
    });
    it('denies author', () => {
      expect(EditorialCapabilities.canArchive('author')).toBe(false);
    });
    it('denies reviewer', () => {
      expect(EditorialCapabilities.canArchive('reviewer')).toBe(false);
    });
  });

  describe('canCorrect', () => {
    it('allows author on own article', () => {
      expect(EditorialCapabilities.canCorrect('author', true)).toBe(true);
    });
    it('denies author on other article', () => {
      expect(EditorialCapabilities.canCorrect('author', false)).toBe(false);
    });
    it('allows publisher on own article', () => {
      expect(EditorialCapabilities.canCorrect('publisher', true)).toBe(true);
    });
    it('denies reviewer', () => {
      expect(EditorialCapabilities.canCorrect('reviewer', true)).toBe(false);
    });
  });

  describe('validate', () => {
    it('allows valid submit_for_review', () => {
      const result = EditorialCapabilities.validate({
        actorRole: 'author',
        action: 'submit_for_review',
        actorId: 'actor-1',
        targetId: 'article-1',
      });
      expect(result.allowed).toBe(true);
    });

    it('denies submit_for_review for reviewer', () => {
      const result = EditorialCapabilities.validate({
        actorRole: 'reviewer',
        action: 'submit_for_review',
        actorId: 'actor-1',
        targetId: 'article-1',
      });
      expect(result.allowed).toBe(false);
      expect(result.reason).toContain('Cannot submit another user\'s draft');
    });

    it('allows review for reviewer who is not author', () => {
      const result = EditorialCapabilities.validate({
        actorRole: 'reviewer',
        action: 'review',
        actorId: 'reviewer-1',
        targetId: 'article-1',
      });
      expect(result.allowed).toBe(true);
    });

    it('allows review for reviewer who is not author', () => {
      const result = EditorialCapabilities.validate({
        actorRole: 'reviewer',
        action: 'review',
        actorId: 'reviewer-1',
        targetId: 'article-1',
      });
      expect(result.allowed).toBe(true);
    });

    it('allows schedule for publisher', () => {
      const result = EditorialCapabilities.validate({
        actorRole: 'publisher',
        action: 'schedule',
        actorId: 'publisher-1',
        targetId: 'article-1',
      });
      expect(result.allowed).toBe(true);
    });

    it('denies schedule for author', () => {
      const result = EditorialCapabilities.validate({
        actorRole: 'author',
        action: 'schedule',
        actorId: 'author-1',
        targetId: 'article-1',
      });
      expect(result.allowed).toBe(false);
    });

    it('allows correct for author on own article', () => {
      const result = EditorialCapabilities.validate({
        actorRole: 'author',
        action: 'correct',
        actorId: 'author-1',
        targetId: 'article-1',
      });
      expect(result.allowed).toBe(true);
    });

    it('allows correct for author on other article', () => {
      const result = EditorialCapabilities.validate({
        actorRole: 'author',
        action: 'correct',
        actorId: 'author-1',
        targetId: 'article-2',
      });
      expect(result.allowed).toBe(true);
    });

    it('returns false for unknown action', () => {
      const result = EditorialCapabilities.validate({
        actorRole: 'author',
        action: 'unknown_action',
        actorId: 'author-1',
        targetId: 'article-1',
      });
      expect(result.allowed).toBe(false);
      expect(result.reason).toContain('Unknown action');
    });
  });
});
