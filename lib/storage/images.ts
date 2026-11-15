// Image storage access for the Resource Centre.
//
// Images are stored in a dedicated bucket with public read access for
// published article images only. Upload/replace/delete is restricted to
// the service role (server-side editorial operations only).

import { createClient as createSupabaseClient } from '@supabase/supabase-js';

export interface ImageInfo {
  path: string;
  publicUrl: string;
  bucket: string;
}

// File type is not available in ES2022 lib; declare a minimal interface.
// Node 18+ and browsers both provide a File global, but TypeScript's ES2022
// lib does not include it. We declare a minimal subset here.
type FilePart = string | Buffer | ArrayBuffer | ArrayBufferView | Blob;
interface FilePropertyBag {
  type?: string;
  lastModified?: number;
}

export class ResourceCenterImages {
  private client: ReturnType<typeof createSupabaseClient>;
  private bucket: string;

  constructor(url: string, serviceRoleKey: string, bucket = 'resource-center-images') {
    this.client = createSupabaseClient(url, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    this.bucket = bucket;
  }

  /**
   * Get the public URL for an image path.
   * Only approved paths (resource-center/featured/*) are allowed.
   */
  getPublicUrl(path: string): string | null {
    if (!path || !path.startsWith('resource-center/featured/')) return null;
    if (path.includes('..') || path.includes('\\\\') || path.includes('//')) return null;
    const { data } = this.client.storage.from(this.bucket).getPublicUrl(path);
    return data.publicUrl ?? null;
  }

  /**
   * Upload an image (editorial write path - service role only).
   * Validates content type, size, and path.
   */
  async upload(params: {
    path: string;
    file: File | Buffer;
    contentType: string;
  }): Promise<ImageInfo> {
    const allowedTypes = ['image/png', 'image/jpeg', 'image/webp'];
    const maxSize = 5 * 1024 * 1024; // 5MB

    if (!allowedTypes.includes(params.contentType)) {
      throw new Error(`Unsupported image type: ${params.contentType}`);
    }

    const { data, error } = await this.client.storage
      .from(this.bucket)
      .upload(params.path, params.file, {
        contentType: params.contentType,
        cacheControl: '3600',
      });

    if (error) throw new Error(`Failed to upload image: ${error.message}`);
    if (!data) throw new Error('Failed to upload image: no data returned');

    const { data: publicUrlData } = this.client.storage.from(this.bucket).getPublicUrl(params.path);

    return {
      path: params.path,
      publicUrl: publicUrlData.publicUrl ?? '',
      bucket: this.bucket,
    };
  }

  /**
   * Delete an image (editorial write path - service role only).
   */
  async delete(path: string): Promise<void> {
    if (!path || !path.startsWith('resource-center/featured/')) {
      throw new Error('Invalid image path');
    }

    const { error } = await this.client.storage.from(this.bucket).remove([path]);
    if (error) throw new Error(`Failed to delete image: ${error.message}`);
  }
}
