-- =============================================================================
-- Australian BAS Tax Reset — cross-project migration
--
-- Run this once in the Supabase SQL Editor. Both Joe's Handyman and PK
-- Woodworking point at the same Supabase project, so this single script
-- creates a tax-payments table for each app, each matching that app's own
-- existing table conventions:
--
--   - handyman_tax_payments : flat columns + open RLS, matching
--     handyman_invoices / handyman_manual_income / handyman_expenses
--     (see schema.sql in the Joe's Handyman repo).
--   - pkw_tax_payments      : id / user_id / jsonb `data` + per-user RLS,
--     matching quotes / manual_income / expenses (see supabase/schema.sql
--     in the PK Woodworking repo).
--
-- Safe to re-run: uses IF NOT EXISTS / DROP POLICY IF EXISTS throughout.
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- handyman_tax_payments
-- One row per logged BAS/PAYG payment. Logging a payment here is what
-- calculateRollingPAYGBas() (src/utils/taxEngine.js) uses to "reset" the
-- rolling PAYG-due estimate — only income dated after the most recent
-- payment_date counts going forward.
-- -----------------------------------------------------------------------------
create table if not exists public.handyman_tax_payments (
  id             uuid primary key default gen_random_uuid(),
  payment_date   date not null default current_date,
  amount         numeric(12, 2) not null default 0,
  financial_year text not null,
  created_at     timestamptz not null default now()
);

comment on table public.handyman_tax_payments is 'Logged BAS/PAYG tax payments; resets the rolling PAYG-due calculation.';

create index if not exists idx_handyman_tax_payments_date on public.handyman_tax_payments (payment_date);
create index if not exists idx_handyman_tax_payments_fy   on public.handyman_tax_payments (financial_year);

alter table public.handyman_tax_payments enable row level security;

drop policy if exists "Allow all access to handyman_tax_payments" on public.handyman_tax_payments;
create policy "Allow all access to handyman_tax_payments"
  on public.handyman_tax_payments for all
  using (true)
  with check (true);

-- -----------------------------------------------------------------------------
-- pkw_tax_payments
-- Mirrors PK Woodworking's existing per-user tables exactly: one row per
-- logged payment, whole payload as JSONB, scoped to auth.uid() the same
-- way quotes/manual_income/expenses already are. That app's PIN screen
-- signs into one fixed Supabase Auth account, so this RLS is what actually
-- makes the PIN a real security boundary (unlike Handyman's open-anon-key
-- model above).
--
-- Expected shape of `data`, matching what src/utils/taxEngine.js expects
-- once mapped: { payment_date: 'YYYY-MM-DD', amount: number,
-- financial_year: 'YYYY-YYYY' }.
-- -----------------------------------------------------------------------------
create table if not exists public.pkw_tax_payments (
  id         uuid primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

comment on table public.pkw_tax_payments is 'Logged BAS/PAYG tax payments for PK Woodworking; resets the rolling PAYG-due calculation.';

create index if not exists pkw_tax_payments_user_id_idx on public.pkw_tax_payments (user_id);

alter table public.pkw_tax_payments enable row level security;

drop policy if exists "pkw_tax_payments_select_own" on public.pkw_tax_payments;
drop policy if exists "pkw_tax_payments_insert_own" on public.pkw_tax_payments;
drop policy if exists "pkw_tax_payments_update_own" on public.pkw_tax_payments;
drop policy if exists "pkw_tax_payments_delete_own" on public.pkw_tax_payments;
create policy "pkw_tax_payments_select_own" on public.pkw_tax_payments for select using (auth.uid() = user_id);
create policy "pkw_tax_payments_insert_own" on public.pkw_tax_payments for insert with check (auth.uid() = user_id);
create policy "pkw_tax_payments_update_own" on public.pkw_tax_payments for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "pkw_tax_payments_delete_own" on public.pkw_tax_payments for delete using (auth.uid() = user_id);
