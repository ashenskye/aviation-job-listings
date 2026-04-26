-- Public bucket URLs can remain accessible without allowing anonymous object listing.
-- Drop broad SELECT policy to prevent unauthenticated path enumeration.
drop policy if exists "company_assets_read_public" on storage.objects;
