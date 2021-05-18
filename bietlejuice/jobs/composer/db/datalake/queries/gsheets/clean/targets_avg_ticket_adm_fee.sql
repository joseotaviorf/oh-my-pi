SELECT
	NULLIF(year, '') AS year,
	NULLIF(month, '') AS month,
	NULLIF(quarter, '') AS quarter,
	CAST(REPLACE(ticket_medio,',','') AS FLOAT) AS ticket_medio,
	CAST(REPLACE(adm_fee,',','') AS FLOAT) AS adm_fee,
	CAST(REPLACE(brokerage_fee,',','') AS FLOAT) AS brokerage_fee,
	CAST(REPLACE(new_rentals,',','') AS FLOAT) AS new_rentals,
	CAST(REPLACE(ongoing_rentals,',','') AS FLOAT) AS ongoing_rentals,
	CAST(REPLACE(ended_rentals,',','') AS FLOAT) AS ended_rentals,
	CAST(REPLACE(ticket_medio_ongoing_rentals,',','') AS FLOAT) AS ticket_medio_ongoing_rentals,
	CAST(REPLACE(adm_fee_ongoing_rentals,',','') AS FLOAT) AS adm_fee_ongoing_rentals
FROM
	datalake_gsheets_raw.targets_avg_ticket_adm_fee