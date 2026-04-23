# Aviation Job Listings

Flutter app for aviation job discovery and employer job posting workflows.

## Run

1. Install Flutter stable SDK.
2. Run `flutter pub get`.
3. Start with `flutter run`.

## Deploy to Vercel (Web)

This repository includes:
- `scripts/vercel-build.sh` to build Flutter web on Vercel.
- `vercel.json` to use `build/web` output and support SPA route rewrites.

Steps:
1. Push this repository to GitHub.
2. In Vercel, create a new project by importing the repository.
3. Add project environment variables:
	- `SUPABASE_URL`
	- `SUPABASE_PUBLISHABLE_KEY`
4. Deploy. Vercel will run the build command from `vercel.json` automatically.

## Compact Changelog

- 2026-04-22: Extended integration tests with instructor certification flow scenarios (apply flow with CFI/CFII hours and profile matching).
- 2026-04-22: Added real-time implied instructor certificate checks to seeker qualifications editor (displays "Required by hours" chips matching job form pattern).
- 2026-04-22: Normalized instructor hour comparisons across all matching and scoring paths (profile matching, applicant review, job details, seeker editor).
- 2026-04-22: Added "Required by hours" reminder chips for instructor certificates in job create/edit forms (CFI, CFII, MEI parallel to existing Tailwheel/Multi-Engine pattern).
- 2026-04-03: Added end-to-end apply flow coverage in widget tests (employer create -> job seeker apply).
- 2026-04-03: Refined match messaging for clearer confidence and requirement guidance (badge tooltip and detail wording).
- 2026-04-03: Kept match comparison outputs concise and action-oriented ("Not yet met" and progress wording).
