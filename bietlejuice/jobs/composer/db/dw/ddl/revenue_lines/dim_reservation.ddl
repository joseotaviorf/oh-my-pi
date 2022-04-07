CREATE TABLE IF NOT EXISTS revenue_lines.dim_reservation
(
	sk_reservation BIGINT NOT NULL
	,status VARCHAR(255)
	,installments INTEGER
	,cancellation_reason VARCHAR(255)
	,value NUMERIC(19,2)
	,ts_created TIMESTAMP
	,ts_load TIMESTAMP
	,PRIMARY KEY (sk_reservation)
)
DISTSTYLE KEY
 DISTKEY (sk_reservation)
;
ALTER TABLE revenue_lines.dim_reservation owner to databricks;