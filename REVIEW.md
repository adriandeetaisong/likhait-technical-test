# Codebase Review

A review pass over the entire repository, done after completing TICKETS.md (BUG-001, FEATURE-001, BONUS-001). Method: read every source file in `frontend/src`, the whole Rails app, specs, seeds, Docker/CI config; verified suspicions against the running stack; checked specifically for injection/XSS vectors, mass-assignment, and silent-failure paths.

**Verified clean:** all SQL goes through parameterized ActiveRecord; both controllers use strong parameters; no `dangerouslySetInnerHTML`/`eval`/`innerHTML` anywhere in the frontend; React's default escaping covers rendered user data.

Severity: **high** = fix before anything real touches this · **medium** = fix soon · **low** = hygiene.

## Fixed during this review

| Issue | Fixed in |
|---|---|
| Edit-expense form silently dropped category changes (name sent, `category_id` expected; strong params discarded it with a 200) | PR #5 |
| Stale pagination page: switching months while on page 2+ rendered an empty table with no way back | review-fixes PR |
| `new Date("YYYY-MM-DD")` parses as UTC midnight — wrong day shown/submitted in UTC-negative timezones, and the edit form could persist the shifted date | review-fixes PR |
| `seeds.rb` hardcoded end date (2026-02-18) vs. the new future-date validation — any seed run before that date would crash mid-seed; clamped to `Date.current` | review-fixes PR |
| Broken factories (`payer_name` remnant; static category name colliding with the uniqueness validation) | review-fixes PR |
| Docker setup unbootable from a fresh clone (5 separate causes) | PR #1 |
| Spec asserting `amount` as a string while the API returns a number (suite was red) | PR #2 |

## Security

- **No authentication or authorization (high, presumably out of scope for the assessment).** Every endpoint is public: anyone can create, update, or delete expenses and categories. Fine for a local demo; the first thing to add before any deployment.
- **CORS is wide open (medium).** `config/initializers/cors.rb` allows `origins "*"` with all methods/headers. Tighten to the frontend origin once deployed.
- **Dev credentials committed (low).** MySQL root/user passwords live in `docker-compose.yml`. Acceptable for local dev; production already expects `DATABASE_*` env vars and `SECRET_KEY_BASE` — keep it that way.

## Correctness & data integrity

- **`Expense` still lacks basic validations (high — likely intentional exercise material).** Negative amounts and empty descriptions are accepted, and the request specs *assert* that behavior. Now that `Category.name` and the future-date rule exist, the same treatment for `amount > 0` and `description` presence is the obvious next step — including flipping those two specs to expect 422.
- **Deleting a category destroys its expenses (medium).** `Category has_many :expenses, dependent: :destroy` makes category deletion silently cascade. With no delete-category UI today this is latent, but any future category-management UI needs a guard (restrict with error, or reassign expenses first).
- **Seeding is destructive and runs on every boot (medium).** The compose command runs `rails db:seed` on every backend start, and `seeds.rb` `destroy_all`s first — every container restart wipes and regenerates all data. Also not concurrency-safe (two overlapping runs race the unique `categories.name` index). Gate seeding behind a flag or an empty-database check.
- **Unvalidated `update` path (low).** `PUT /api/expenses/:id` accepts the same invalid values as create did (negative amounts, blank descriptions); fixing the model validations fixes both at once.

## Architecture

- **The frontend owns category name→id resolution (medium).** Writes send a category *name* that `services/api.ts` maps to an id by re-fetching the entire category list — the root cause of the bug fixed in PR #5. Cleaner: have the API accept the id directly (form binds to `category_id`), or let the API resolve names server-side. The current extra round-trip per create/edit is also a small race window.
- **Dead code (low).** `vibes/ItemTable` and `vibes/ColumnBase` are exported but imported nowhere (`ItemTable` also uses `key={index}` with `any[]` — don't adopt as-is); `fetchExpenses` (unfiltered) in `services/api.ts` is shadowed/unused; `MonthlySummary`/`TopCategory`/`DayExpenses` types in `types.ts` are unused. Either use them or delete them — the barrel export makes dead code look supported.
- **`react-router-dom` installed but unused (low).** Page switching is manual `useState` in `App.tsx`. Fine at one page; adopt the router or drop the dependency.
- **`VITE_API_URL` set in compose but ignored (low).** `services/api.ts` hardcodes `http://localhost:3000/api` — read the env var so the frontend works when the backend isn't on localhost:3000.
- **Duplicated layout constants (low).** Sidebar widths (`80px`/`360px`) are hardcoded in both `App.tsx` and `Sidebar.tsx`.
- **Accessibility gaps (low).** `vibes/Modal` has no `role="dialog"`/`aria-modal`/focus trap; `TextField`/`SelectBox` labels aren't associated with their inputs (`htmlFor`/`id`); `SelectBox` always injects a placeholder `<option>`, so it can't express a required select.

## Performance

- **No server-side pagination (medium).** `GET /api/expenses` without params returns every row (~4,300 with seeds) as one JSON array; month filtering helps but a busy month is still unbounded, and the table paginates client-side only. Add `LIMIT`/offset or cursor pagination when data grows.
- **Money serialized as float (low).** `amount.to_f` in `format_expense` invites float artifacts in client arithmetic. Strings or integer cents are the safe conventions for money over JSON.
- **Seeding is ~4,300 individual INSERTs (low).** No transaction/`insert_all`; adds minutes to every container start.

## DX, CI & testing

- **CI cannot run as committed (high).** `backend/.github/workflows/ci.yml` sits outside the root `.github/` so GitHub never picks it up; every step assumes CWD `backend/` (`ruby-version: .ruby-version`, `bundler-cache`, `bin/*` paths all resolve wrong from the repo root); the test step runs Minitest-style `rails test test:system` though the project uses RSpec; `DATABASE_URL` doesn't match the `DATABASE_*` contract in `database.yml`; the MySQL image is unpinned; Chrome/system-test scaffolding is vestigial. Fix: move to root `.github/workflows/`, set `working-directory: backend`, run `bundle exec rspec`, provision the test DB with matching credentials.
- **Dead test dependencies (low).** `shoulda-matchers` and `database_cleaner-active_record` are in the Gemfile but configured nowhere (no `spec/support/`, support glob commented out). Configure or remove.
- **No frontend tests at all (medium).** `frontend/package.json` has no test runner; all frontend verification is manual. Vitest + Testing Library would fit the Vite stack.
- **Container `RAILS_ENV` leaks into the test runner (low, hit during this review).** Compose sets `RAILS_ENV=development`, so `bundle exec rspec` inside the container runs against the *development* database unless invoked as `RAILS_ENV=test bundle exec rspec` — the specs initially "failed" against seeded dev data. Worth a note in the README or a compose override for test runs.
- **Specs that assert buggy behavior (low, intentional).** The negative-amount and empty-description specs document bugs as features; convert them to 422 assertions when validations land.

## If this were going to production, in order

1. Authentication + authorization; lock down CORS.
2. `Expense` validations (`amount > 0`, `description` presence) and flip the two specs.
3. Stop reseeding on boot; make seeds idempotent and non-destructive.
4. Working CI (root `.github/`, RSpec, correct DB env).
5. Server-side pagination on `GET /api/expenses`.
6. Category id-based writes from the frontend (drop name resolution).
7. Money as string/cents; then the low-priority hygiene items above.
