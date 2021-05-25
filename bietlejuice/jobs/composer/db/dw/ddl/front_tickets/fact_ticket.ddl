DROP TABLE IF EXISTS front_tickets.fact_ticket;
CREATE TABLE IF NOT EXISTS front_tickets.fact_ticket (
    sk_ticket BIGINT,
    sk_taxonomy VARCHAR(40),
    sk_channel VARCHAR(40),
    sk_first_department VARCHAR(40),
    sk_last_department VARCHAR(40),
    channel VARCHAR(5),
    csat_score INTEGER,
    status VARCHAR(20),
    minutes_full_resolution_time_calendar INTEGER, 
    first_department VARCHAR(100),
    last_department VARCHAR(100),
    number_of_departments INTEGER,
    number_of_tasks INTEGER,
    back_ticket BIGINT,
    is_resolution_survey BOOLEAN,
    has_anwsered_survey BOOLEAN,
    has_back_ticket BOOLEAN,
    is_open_back_ticket BOOLEAN,
    is_crr BOOLEAN,
    is_fcr BOOLEAN,
    has_transfers BOOLEAN,
    ts_started TIMESTAMP,
    ts_closed TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE front_tickets.fact_ticket OWNER TO airflow;