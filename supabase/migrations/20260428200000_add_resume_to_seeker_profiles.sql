-- Add resume_url and resume_file_name columns to job_seeker_profiles
alter table job_seeker_profiles
  add column if not exists resume_url        text    not null default '',
  add column if not exists resume_file_name  text    not null default '';

-- Create a private bucket for seeker resume files
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'seeker-resumes',
  'seeker-resumes',
  false,
  10485760,   -- 10 MB
  array[
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/rtf',
    'text/plain'
  ]
)
on conflict (id) do nothing;

-- Owners can upload into their own user-id-prefixed folder
drop policy if exists "seeker_resumes_insert_own" on storage.objects;
create policy "seeker_resumes_insert_own"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'seeker-resumes'
  and auth.uid()::text = (storage.foldername(name))[1]
);

-- Owners can read their own files
drop policy if exists "seeker_resumes_select_own" on storage.objects;
create policy "seeker_resumes_select_own"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'seeker-resumes'
  and auth.uid()::text = (storage.foldername(name))[1]
);

-- Owners can delete their own files
drop policy if exists "seeker_resumes_delete_own" on storage.objects;
create policy "seeker_resumes_delete_own"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'seeker-resumes'
  and auth.uid()::text = (storage.foldername(name))[1]
);
