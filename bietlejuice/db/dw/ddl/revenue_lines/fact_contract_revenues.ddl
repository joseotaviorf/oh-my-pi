CREATE TABLE IF NOT EXISTS revenue_lines.fact_contract_revenues
(
    sk_contract_revenue BIGINT NOT NULL
    ,sk_late_payments_rent BIGINT
    ,sk_late_payments_condo   BIGINT 
    ,sk_month_rental_anticipation BIGINT
    ,sk_long_term_rental_anticipation BIGINT
    ,sk_brokerage_finance BIGINT
    ,sk_reservation BIGINT
    ,sk_credit_card_payment BIGINT
    ,sk_rental_guarantee BIGINT
    ,sk_rental_guarantee_charge BIGINT
    ,sk_month_start BIGINT
    ,due_monthly_revenue NUMERIC (19,2)
    ,paid_monthly_revenue NUMERIC (19,2)
    ,ts_load TIMESTAMP
    ,PRIMARY KEY (sk_contract_revenue)
)
DISTSTYLE KEY
 DISTKEY (sk_contract_revenue)
;

ALTER TABLE revenue_lines.fact_contract_revenues owner to databricks;
