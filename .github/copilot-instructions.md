# Copilot Instructions for Aviation Job Listings

These instructions define coding standards, preferred libraries, and architectural rules for this Flutter repository.

## Tech Stack and Runtime
- Use Dart and Flutter only.
- Keep code compatible with stable Flutter SDK.
- Do not introduce platform-specific code unless explicitly required.

## Preferred Libraries
- Use `package:flutter/material.dart` for UI.
- Use `package:http/http.dart` for REST calls.
- Use `package:shared_preferences/shared_preferences.dart` for simple local persistence (favorites, lightweight user settings).
- Avoid adding new third-party dependencies if Flutter SDK or existing dependencies already solve the problem.
- If a new dependency is truly needed, prefer well-maintained packages with clear null-safety support.

## Architecture Rules
- Keep app entry in `lib/main.dart` unless a refactor is requested.
- Use `StatefulWidget` and local state for page-level interactions in this app.
- Keep model classes immutable (`final` fields, `const` constructors where practical).
- Preserve existing model JSON APIs (`fromJson`, `toJson`) and avoid breaking wire formats.
- Keep business logic in methods on the state class when no dedicated service layer exists.
- Reuse existing fields and naming patterns before introducing new state variables.

## Data and Networking
- Use async/await for all network and storage operations.
- Always handle network failures with `try/catch` and provide a user-safe fallback.
- Keep request timeouts explicit.
- Do not block UI during async work; reflect loading state in widgets.

## UI and UX Conventions
- Use Material widgets and existing spacing patterns (`SizedBox`, `Padding`, `EdgeInsets`).
- Match existing visual grouping style (bordered `Container` blocks for grouped checkbox sections).
- Prefer readable forms with clear labels and validation feedback via `SnackBar`.
- Keep strings user-friendly and aviation-domain specific.
- Preserve current tab structure and profile behavior unless explicitly asked to redesign.

## State and Mutations
- Wrap UI-impacting state updates in `setState`.
- Keep mutations minimal and localized.
- After mutating collections used by the UI, ensure state is updated in the same interaction.

## Code Style
- Follow lints from `analysis_options.yaml`.
- Use meaningful method and variable names.
- Keep methods focused; extract helper methods if a widget build section grows too large.
- Add comments only when logic is not self-evident.
- Prefer `const` constructors/widgets when possible.

## Testing and Validation
- For behavior changes, update or add tests in `test/` when practical.
- Ensure new code compiles cleanly and does not introduce analyzer warnings.
- Prefer small, incremental changes that preserve existing behavior.

## Change Safety
- Do not remove existing features unless explicitly requested.
- Do not rewrite large sections for stylistic reasons.
- Keep backward-compatible data behavior for saved favorites and job listing fields.

## Copilot Behavior Preferences
- Propose minimal diffs first.
- Ask before major architectural refactors.
- When implementing UI tweaks, preserve existing component structure and only change required sections.
- When uncertain about product behavior, choose conservative defaults and keep current UX intact.
