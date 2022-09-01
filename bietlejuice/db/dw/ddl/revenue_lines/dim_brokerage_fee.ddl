CREATE TABLE IF NOT EXISTS revenue_lines.dim_brokerage_fee
(
    sk_brokerage_fee VARCHAR(255)
    ,id_contract_ebdb BIGINT
    ,brokerage_share VARCHAR(255)
    ,invoice_payment_status VARCHAR(255)
    ,first_rental_commission DOUBLE PRECISION
    ,agent_brokerage_share DOUBLE PRECISION
    ,brokerage_split_percentage DOUBLE PRECISION
    ,prod_theorical_amount DOUBLE PRECISION
    ,invoice_theorical_amount DOUBLE PRECISION
    ,invoice_paid_amount DOUBLE PRECISION
    ,accrual_year_month VARCHAR(20)
    ,dt_due DATE
    ,dt_paid DATE
    ,dt_contract_start DATE
	,PRIMARY KEY (sk_brokerage_fee)
)
DISTSTYLE KEY
 DISTKEY (sk_brokerage_fee)
;
ALTER TABLE revenue_lines.dim_brokerage_fee owner to databricks;