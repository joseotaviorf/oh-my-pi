CREATE TABLE IF NOT EXISTS revenue_lines.dim_management_fee
(
    sk_management_fee VARCHAR(255)
    ,id_contract_ebdb BIGINT
    ,management_fee_share VARCHAR(255)
    ,payment_status VARCHAR(255
    ,monthly_administration_fee DECIMAL(5,4)
    ,administration_split_percentage DOUBLE PRECISION
    ,prod_theorical_amount DOUBLE PRECISION
    ,invoice_theorical_amount DECIMAL(26,2)
    ,invoice_paid_amount DECIMAL(38,2)
    ,accrual_year_month INTEGER
    ,dt_due DATE
    ,dt_paid DATE
	,PRIMARY KEY (sk_management_fee)
)
DISTSTYLE KEY
 DISTKEY (sk_management_fee)
;
ALTER TABLE revenue_lines.dim_management_fee owner to databricks;