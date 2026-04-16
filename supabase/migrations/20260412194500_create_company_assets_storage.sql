insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'company-assets',
  'company-assets',
  true,
  5242880,
  array['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/svg+xml']
)
on conflict (id) do nothing;

drop policy if exists "company_assets_read_public" on storage.objects;
create policy "company_assets_read_public"
on storage.objects
for select
using (bucket_id = 'company-assets');

drop policy if exists "company_assets_insert_own_folder" on storage.objects;
create policy "company_assets_insert_own_folder"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'company-assets'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "company_assets_update_own_folder" on storage.objects;
create policy "company_assets_update_own_folder"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'company-assets'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'company-assets'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "company_assets_delete_own_folder" on storage.objects;
create policy "company_assets_delete_own_folder"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'company-assets'
  and auth.uid()::text = (storage.foldername(name))[1]
);
