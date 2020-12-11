DROP TABLE IF EXISTS quinto_messenger.dim_quinto_messenger_agent;
CREATE TABLE IF NOT EXISTS quinto_messenger.dim_quinto_messenger_agent (
    sk_quinto_messenger_agent VARCHAR(100) PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(50),
    location VARCHAR(25),
    skills VARCHAR(200),
    ts_updated TIMESTAMP
)
ALTER TABLE quinto_messenger.dim_quinto_messenger_agent OWNER TO airflow;
