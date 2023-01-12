DROP TABLE IF EXISTS sale.fact_daily_listings_available_hours;
CREATE TABLE sale.fact_daily_listings_available_hours (
	sk_date BIGINT,
	sk_house BIGINT,
	sk_region BIGINT,
    status_history VARCHAR,
    week_available_hours BIGINT,
    workdays_available_hours BIGINT,
    monday_available_hours BIGINT,
    tuesday_available_hours BIGINT,
    wednesday_available_hours BIGINT,
    thursday_available_hours BIGINT,
    friday_available_hours BIGINT,
    saturday_available_hours BIGINT,
    sunday_available_hours BIGINT
);
ALTER TABLE sale.fact_daily_listings_available_hours OWNER TO airflow;