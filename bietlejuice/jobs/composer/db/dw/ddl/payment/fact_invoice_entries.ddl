drop table if exists payment.fact_invoice_entries;
create table if not exists payment.fact_invoice_entries (
    sk_invoice_entry bigint primary key,
    sk_invoice bigint,
    sk_contract bigint,
    sk_contract_user bigint,
    sk_region bigint,
    sk_created_date int,
    sk_due_date int,
    sk_paid_date int,
    brl_entry_due_amount decimal(16,3),
    brl_entry_paid_amount decimal(38,2),
    ts_created timestamp,
    ts_load timestamp
)