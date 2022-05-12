DROP TABLE if exists payment.dim_invoice;
CREATE TABLE if not exists payment.dim_invoice (
    sk_invoice BIGINT primary key,
    frequency VARCHAR(50),
    payment_status VARCHAR(50),
    negotiation_status VARCHAR(255),
    closing_mode VARCHAR(255),
    paid_via VARCHAR(255),
    "user" VARCHAR(50),
    due_amount DECIMAL(13,2),
    paid_amount DECIMAL(13,2),
    accrual_year_month INT,
    ts_created TIMESTAMP,
    dt_sent DATE,
    dt_due DATE,
    dt_paid DATE,
    ts_load TIMESTAMP
);

ALTER TABLE payment.dim_invoice OWNER TO databricks;
