CREATE TABLE IF NOT EXISTS revenue_lines.dim_reservation
(
	sk_reservation BIGINT NOT NULL
	,id_contract BIGINT
	,status VARCHAR(255)
	,cancellation_reason VARCHAR(255)
	,total_installments INTEGER
	,monthly_value NUMERIC(19,2)
	,total_value NUMERIC(19,2)
	,accrual_month VARCHAR(255)
	,dt_end_payment DATE
	,dt_created DATE
	,ts_load TIMESTAMP
	,PRIMARY KEY (sk_reservation)
)
DISTSTYLE KEY
 DISTKEY (sk_reservation)
;
ALTER TABLE revenue_lines.dim_reservation owner to databricks;