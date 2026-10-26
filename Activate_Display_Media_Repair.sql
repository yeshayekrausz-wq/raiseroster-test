-- Repeat-safe private media storage setup. No stored files or students are deleted.
-- Optional media storage for the Motivation display. Requires Supabase Storage.
BEGIN;
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('motivation-media','motivation-media',false,26214400,ARRAY['image/png','image/jpeg','image/webp','video/mp4','video/webm','application/pdf'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=EXCLUDED.file_size_limit,allowed_mime_types=EXCLUDED.allowed_mime_types;
DROP POLICY IF EXISTS motivation_media_read ON storage.objects;
CREATE POLICY motivation_media_read ON storage.objects FOR SELECT TO authenticated
USING(bucket_id='motivation-media' AND EXISTS(SELECT 1 FROM public.organization_members m WHERE m.user_id=auth.uid() AND m.role::text IN ('admin','super_admin') AND m.organization_id::text=(storage.foldername(name))[1]));
DROP POLICY IF EXISTS motivation_media_insert ON storage.objects;
CREATE POLICY motivation_media_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK(bucket_id='motivation-media' AND EXISTS(SELECT 1 FROM public.organization_members m WHERE m.user_id=auth.uid() AND m.role::text IN ('admin','super_admin') AND m.organization_id::text=(storage.foldername(name))[1]));
DROP POLICY IF EXISTS motivation_media_delete ON storage.objects;
CREATE POLICY motivation_media_delete ON storage.objects FOR DELETE TO authenticated
USING(bucket_id='motivation-media' AND EXISTS(SELECT 1 FROM public.organization_members m WHERE m.user_id=auth.uid() AND m.role::text IN ('admin','super_admin') AND m.organization_id::text=(storage.foldername(name))[1]));
-- Restrictive boundaries keep older broad Storage policies from opening this bucket.
DROP POLICY IF EXISTS motivation_media_boundary ON storage.objects;
CREATE POLICY motivation_media_boundary ON storage.objects AS RESTRICTIVE FOR ALL TO authenticated
USING(bucket_id<>'motivation-media' OR EXISTS(SELECT 1 FROM public.organization_members m WHERE m.user_id=auth.uid() AND m.role::text IN ('admin','super_admin') AND m.organization_id::text=(storage.foldername(name))[1]))
WITH CHECK(bucket_id<>'motivation-media' OR EXISTS(SELECT 1 FROM public.organization_members m WHERE m.user_id=auth.uid() AND m.role::text IN ('admin','super_admin') AND m.organization_id::text=(storage.foldername(name))[1]));
DROP POLICY IF EXISTS motivation_media_anonymous_boundary ON storage.objects;
CREATE POLICY motivation_media_anonymous_boundary ON storage.objects AS RESTRICTIVE FOR ALL TO anon
USING(bucket_id<>'motivation-media') WITH CHECK(bucket_id<>'motivation-media');
COMMIT;
SELECT 'MOTIVATION_MEDIA_READY' AS result;
