DROP TABLE IF EXISTS quinto_messenger.dim_task;
CREATE TABLE IF NOT EXISTS quinto_messenger.dim_task (
    sk_task VARCHAR(100) PRIMARY KEY,
    channel VARCHAR(25),
    department VARCHAR(80),
    status VARCHAR(25),
    completion_reason VARCHAR(50),
    customer_type VARCHAR(50),
    contact_motivation VARCHAR(50),
    contact_theme VARCHAR(50),
    ts_created TIMESTAMP,
    ts_updated TIMESTAMP
)
ALTER TABLE quinto_messenger.dim_task OWNER TO airflow;
