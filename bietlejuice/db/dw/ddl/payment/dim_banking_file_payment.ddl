drop table if exists payment.dim_banking_file_payment;
create table if not exists payment.dim_banking_file_payment (
    sk_banking_file_payment varchar(30) primary key,
    format varchar(30),
    type varchar(30),
    version varchar(5),
    bank_name varchar(30),
    user_type varchar(30),
    payment_type varchar(30),
    related_document_type varchar(30),
    invoice_status varchar(30),
    payment_request_status varchar(30),
    status varchar(30),
    accrual_year_month int,
    ts_created timestamp,
    ts_issued timestamp,
    ts_updated timestamp,
    dt_due datetime,
    dt_fine_due datetime,
    dt_paid datetime,
    ts_load timestamp
)