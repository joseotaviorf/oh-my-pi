drop table if exists payment.dim_invoice;
create table if not exists payment.dim_invoice (
    sk_invoice bigint primary key,
    invoice_frequency varchar(50),
    payment_status varchar(50),
    dt_invoice_due datetime,
    dt_invoice_paid datetime,
    ts_load timestamp
)