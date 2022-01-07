drop table if exists payment.dim_invoice_entry;
create table if not exists payment.dim_invoice_entry (
    sk_invoice_entry bigint primary key,
    entry_type varchar(80),
    from_account_type varchar(50),
    to_account_type varchar(50),
    accounting_account varchar(50),
    producer varchar(255),
    description varchar(350),
    invoice_revenue varchar(200),
    accrual_year_month int,
    ts_load timestamp
)