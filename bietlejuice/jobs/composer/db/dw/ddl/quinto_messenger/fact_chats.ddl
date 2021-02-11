DROP TABLE IF EXISTS quinto_messenger.fact_chats;
CREATE TABLE IF NOT EXISTS quinto_messenger.fact_chats (
    sk_chat VARCHAR(100) PRIMARY KEY,
    sk_session VARCHAR(100),
    sk_user BIGINT,
    sk_personal_document VARCHAR(50),
    sk_created_date BIGINT,
    minutes_duration DECIMAL(27,6),
    tasks BIGINT,
    ts_load TIMESTAMP
)
ALTER TABLE quinto_messenger.fact_chats OWNER TO airflow;
