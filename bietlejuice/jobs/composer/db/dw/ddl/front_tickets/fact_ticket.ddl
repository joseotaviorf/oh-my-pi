DROP TABLE IF EXISTS front_tickets.fact_ticket;
CREATE TABLE IF NOT EXISTS front_tickets.fact_ticket (
    sk_ticket BIGINT,
    sk_taxonomy VARCHAR(40),
    sk_channel VARCHAR(40),
    sk_first_department VARCHAR(40),
    sk_last_department VARCHAR(40),
    sk_zendesk_department VARCHAR(40),
    sk_user BIGINT,
    sk_contract BIGINT,
    channel VARCHAR(5),
    csat_score INTEGER,
    status VARCHAR(20),
    minutes_full_resolution_time_calendar DOUBLE PRECISION, 
    first_department VARCHAR(100),
    last_department VARCHAR(100),
    zendesk_department VARCHAR(100),
    total_departments INTEGER,
    total_tasks INTEGER,
    front_or_back VARCHAR(10)
    back_ticket BIGINT,
    resolution_survey BOOLEAN,
    has_answered_csat BOOLEAN,
    has_back_ticket BOOLEAN,
    is_back_ticket_open BOOLEAN,
    is_solved BOOLEAN,
    is_fcr BOOLEAN,
    has_transfers BOOLEAN,
    ts_started TIMESTAMP,
    ts_closed TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE front_tickets.fact_ticket OWNER TO airflow;