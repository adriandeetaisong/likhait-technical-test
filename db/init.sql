-- Create database if not exists
CREATE DATABASE IF NOT EXISTS expense_system_development CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

USE expense_system_development;

-- Schema mirrors the Rails migrations (backend/db/migrate) so the database is
-- usable immediately, while `rails db:migrate` (run by the backend container on
-- every start) remains in charge of the schema:
-- - The unique index on categories.name is intentionally NOT created here;
--   migration 20260218000001 adds it (its add_index is not idempotent).
-- - Seed data comes from `rails db:seed` (backend/db/seeds.rb), which the
--   backend container also runs on start.

CREATE TABLE IF NOT EXISTS categories (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS expenses (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  description VARCHAR(255) NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  date DATE NOT NULL,
  category_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  INDEX index_expenses_on_category_id (category_id),
  CONSTRAINT fk_rails_06966d0da0 FOREIGN KEY (category_id) REFERENCES categories(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
