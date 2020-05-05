drop table if exists payment.dim_invoice;
create table if not exists payment.dim_invoice (
    sk_invoice bigint primary key,
    invoice_frequency varchar(50),
    payment_status varchar(50),
    invoice_due_amount decimal(13,2),
    ts_invoice_created timestamp,
    dt_invoice_sent date,
    dt_invoice_due date,
    dt_invoice_paid date,
    ts_load timestamp
)
