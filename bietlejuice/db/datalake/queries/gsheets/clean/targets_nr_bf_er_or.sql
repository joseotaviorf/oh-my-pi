SELECT
	NULLIF(month, '') AS month,
	NULLIF(year, '') AS year,
	NULLIF(quarter, '') AS quarter,
	NULLIF(weekday, '') AS weekday,
	CAST(REPLACE(new_rentals,',','') AS FLOAT) AS new_rentals,
	CAST(REPLACE(ended_rentals,',','') AS FLOAT) AS ended_rentals,
	CAST(REPLACE(ongoing_rentals,',','') AS FLOAT) AS ongoing_rentals,
	DATE(date) AS dt_date,
	DATE(week_start) AS dt_week_started
FROM
	datalake_gsheets_raw.targets_nr_bf_er_or
