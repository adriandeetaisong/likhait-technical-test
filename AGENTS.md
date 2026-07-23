# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

This is a **full-stack expense tracking application** with calendar-based visualization for managing personal finances. It was created as a take-home technical assessment (see `README.md` and `TICKETS.md`).

- `frontend/` — React 18 + TypeScript 5.3 single-page app, built with Vite 5.
- `backend/` — Ruby 3.3.7 / Rails 7.2 API-only app (`config.api_only = true`), backed by MySQL 8.0.
- `db/init.sql` — SQL script mounted into the MySQL container at first boot; creates the database and tables only (mirrors the Rails schema).
- `docker-compose.yml` — orchestrates `db` (MySQL), `backend` (Rails, port 3000), and `frontend` (Vite dev server, port 5173).

Domain model (two tables):

- `categories` — `name` (string, max 100, unique index). `has_many :expenses, dependent: :destroy`. Model validates `name` for presence, uniqueness (case-insensitive), and length ≤ 100.
- `expenses` — `description` (string), `amount` (decimal 10,2), `date` (date), `category_id` (FK). `belongs_to :category`.

API surface (all under `/api`, JSON only):

- `GET /api/categories` — list categories ordered by name.
- `POST /api/categories` — create a category (`name` required, unique, max 100); 422 with `errors` array on validation failure.
- `GET /api/expenses?year=&month=` — list expenses; optional year/month filter.
- `POST /api/expenses`, `PUT /api/expenses/:id`, `DELETE /api/expenses/:id`.
- Expense JSON responses are hand-built in `Api::ExpensesController#format_expense` (no serializer/jbuilder); the category is returned as a **name string**, not an id/object.

## Build and Run

### Docker (recommended)

```bash
docker compose up
# Frontend: http://localhost:5173
# Backend API: http://localhost:3000/api
```

The backend container runs `bundle install && bundle exec rails db:migrate && bundle exec rails db:seed && bundle exec rails server` on start. Source directories are volume-mounted, so code changes are picked up live (Vite HMR on the frontend; Rails code reloading on the backend).

### Manual setup

```bash
# Backend (requires Ruby 3.3.7 and a local MySQL 8)
cd backend
bundle install
rails db:create db:migrate db:seed
rails server          # port 3000

# Frontend (requires Node 18+)
cd frontend
npm install
npm run dev           # port 5173
npm run build         # type-check (tsc) + vite build
```

Database config is driven by env vars (`DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`); see `backend/config/database.yml` and `docker-compose.yml` for the development defaults (`expense_user` / `expense_password`, db `expense_system_development`).

## Testing

Backend only — the frontend has **no test setup** (no test runner in `frontend/package.json`).

```bash
cd backend
bundle exec rspec                 # full test suite
bundle exec rspec spec/requests/api/expenses_spec.rb   # single file
```

- Framework: RSpec (`rspec-rails`), with Factory Bot (`factory_bot_rails`), Faker, shoulda-matchers, and database_cleaner-active_record.
- Specs run with transactional fixtures (`use_transactional_fixtures = true`); spec type is inferred from file location.
- Existing coverage is thin: request specs for both endpoints (`spec/requests/api/`), mostly-empty model specs, and factories in `spec/factories/`. **Some specs intentionally assert current buggy behavior** (e.g., invalid expenses being created) — read `TICKETS.md` before assuming a passing spec defines correct behavior.
- The test database is `expense_system_test`; `rails_helper.rb` calls `ActiveRecord::Migration.maintain_test_schema!`, so run `rails db:test:prepare` (or `RAILS_ENV=test rails db:create db:schema:load`) if the test DB is missing.

## Code Quality and CI

```bash
cd backend
bundle exec rubocop      # lint (rubocop-rails-omakase style)
bin/brakeman --no-pager  # security static analysis
```

- Ruby style: `rubocop-rails-omakase` (see `backend/.rubocop.yml`) — Omakase defaults, e.g. double-quoted strings, no frozen-string-literal comments. The README asks contributors to run RuboCop before submitting.
- TypeScript: `strict: true`, `noUnusedLocals`, `noUnusedParameters` (`frontend/tsconfig.json`); `npm run build` runs `tsc` first, so type errors break the build. There is no ESLint/Prettier config.
- CI workflow lives at `backend/.github/workflows/ci.yml` (Brakeman + RuboCop + tests with a MySQL service). Note: because it is not in a root-level `.github/` directory, GitHub will not pick it up in this repository layout as-is, and its test step invokes `test test:system` (Minitest-style) even though the project uses RSpec — treat it as a starting template, not a working pipeline.

## Codebase Layout and Conventions

### Backend (`backend/`)

Standard Rails API layout. The app is deliberately small:

- `app/controllers/api/` — all controllers are namespaced under `Api::`; `ApplicationController < ActionController::API` is empty.
- `app/models/` — `Category` and `Expense` only; `Category` validates `name` (presence, uniqueness, length); `Expense` has no validations yet.
- `config/routes.rb` — `namespace :api` block; categories is index/create, expenses is index/create/update/destroy (no `show`).
- `db/migrate/`, `db/schema.rb`, `db/seeds.rb` — schema.rb is the source of truth; seeds generate ~2 years of random sample expenses (Jan 2024 – Feb 2026) across 10 categories.
- Models and controllers use plain Rails idioms; JSON is shaped inline in controllers.

### Frontend (`frontend/src/`)

- `main.tsx` → `App.tsx` — shell with a collapsible `Sidebar`; "routing" is manual `useState` page switching, **not** react-router (although `react-router-dom` is installed, it is unused).
- `pages/HistoryPage.tsx` — the only page; owns expense fetching, year/month selection (synced to URL query params), category breakdown aggregation, and the Add Expense / Add Category modals.
- `components/` — feature components (`CalendarExpenseTable`, `CategoryBreakdown`, `ExpenseForm`, `AddCategoryModal`, `MonthNavigation`, `YearNavigation`, `QuickAddButton`, `Sidebar`).
- `vibes/` — custom in-house component library (`Button`, `TextField`, `SelectBox`, `FormControl`, `Modal`, `ColumnBase`, `ItemTable`, `Pagination`) with a barrel `index.ts`. Reuse these instead of introducing new UI primitives or a CSS framework.
- `services/api.ts` — all backend calls via `fetch`; base URL is hardcoded to `http://localhost:3000/api`.
- `types.ts` — shared TypeScript interfaces (`Expense`, `ExpenseFormData`, etc.).
- `constants/` — `colors.ts` (design tokens), `categoryEmojis.ts`.
- `hooks/`, `utils/` — `useExpenseForm`, `expenseUtils`.

Frontend style conventions:

- Functional components (`React.FC` or plain functions), hooks for state.
- Styling is **inline** via `React.CSSProperties` objects referencing the `COLORS` constants — there is no CSS file or utility framework.
- Mix of default and named exports; `vibes/` components are named exports re-exported from `vibes/index.ts`.

## Git and Contribution Workflow

Per `README.md` (assessment rules): create a dedicated branch per task, open a separate PR per task (never commit everything to `main`), and write thorough PR descriptions. The tasks themselves are specified in `TICKETS.md` (one bug fix, one feature, one bonus). Ensure `bundle exec rspec` and `bundle exec rubocop` pass before opening a PR.

## Security Considerations

- `rack-cors` is configured wide open (`origins "*"`, all methods) in `backend/config/initializers/cors.rb` — acceptable for local development, tighten before any real deployment.
- There is **no authentication or authorization**; all API endpoints are public.
- The `expenses` table has no model-level validations — negative amounts and empty descriptions are currently accepted (see TICKETS.md / request specs).
- MySQL credentials in `docker-compose.yml` are development-only defaults; production expects `DATABASE_*` env vars and `SECRET_KEY_BASE` (see README "Environment Configuration").
- Brakeman is available (`bin/brakeman`) for security scanning; run it when touching backend code.

## Known Quirks and Inconsistencies

These are real as of writing — verify before relying on them, and don't "fix" them accidentally while doing unrelated work (TICKETS.md defines the sanctioned tasks):

- `db/init.sql` mirrors the Rails schema but creates **tables only** — the unique index on `categories.name` is deliberately left to migration `20260218000001` (its `add_index` is not idempotent), and all seed data comes from `rails db:seed` on backend start. Keep it in sync with `backend/db/schema.rb` if migrations change.
- `spec/factories/expenses.rb` still references the removed `payer_name` attribute, so the expense factory is broken.
- `Api::ExpensesController#index` orders by `date DESC` (tiebroken by `id DESC`) and filters the month by `date` — `created_at` is only a record-keeping timestamp. (This mismatch was BUG-001 in `TICKETS.md`; it is fixed.)
- `ExpenseForm` fetches its category options from `GET /api/categories` on mount (the hardcoded `EXPENSE_CATEGORIES` constant was removed in FEATURE-001); `createExpense` still resolves a category name to an id by re-fetching all categories.
- `docker-compose.yml` sets `VITE_API_URL`, but `frontend/src/services/api.ts` ignores it (hardcoded base URL).
- The seed date range (2024–2026) is anchored to the assessment timeframe; the calendar UI defaults to the current month, which may show no data without navigating.
