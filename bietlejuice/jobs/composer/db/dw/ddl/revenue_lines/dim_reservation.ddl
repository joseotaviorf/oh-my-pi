CREATE TABLE IF NOT EXISTS revenue_lines.dim_reservation
(
	sk_reservation BIGINT NOT NULL  ENCODE az64
	,status VARCHAR(255)   ENCODE lzo
	,installments INTEGER   ENCODE az64
	,cancellation_reason VARCHAR(255)   ENCODE lzo
	,value NUMERIC(19,2)   ENCODE az64
	,ts_created TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
	,PRIMARY KEY (sk_reservation)
)
DISTSTYLE KEY
 DISTKEY (sk_reservation)
;
ALTER TABLE revenue_lines.dim_reservation owner to databricks;