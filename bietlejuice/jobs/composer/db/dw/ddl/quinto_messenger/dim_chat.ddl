DROP TABLE IF EXISTS quinto_messenger.dim_chat;
CREATE TABLE IF NOT EXISTS quinto_messenger.dim_chat (
    sk_chat VARCHAR(100) PRIMARY KEY,
    channel VARCHAR(25),
    customer_phone VARCHAR(25),
    status VARCHAR(25),
    is_forwarded BOOLEAN,
    ts_created TIMESTAMP,
    ts_updated TIMESTAMP,
    ts_load TIMESTAMP
)
ALTER TABLE quinto_messenger.dim_chat OWNER TO airflow;
