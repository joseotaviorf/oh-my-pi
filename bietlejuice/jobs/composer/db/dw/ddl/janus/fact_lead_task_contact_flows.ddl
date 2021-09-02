DROP TABLE IF EXISTS janus.fact_lead_task_contact_flows;

CREATE TABLE janus.fact_lead_task_contact_flows (
    sk_lead BIGINT,
    sk_task VARCHAR(64),
    sk_imported_to_task_references_date INTEGER,
    ts_imported_to_task_references TIMESTAMP,
    is_active_in_task_references BOOLEAN,
    sk_imported_to_mailing_list_date INTEGER,
    ts_imported_to_mailing_list TIMESTAMP,
    is_active_in_mailing_list BOOLEAN,
    sk_first_call_date INTEGER,
    ts_first_call TIMESTAMP,
    sk_first_connection_date INTEGER,
    ts_first_connection TIMESTAMP,
    is_mailing_active BOOLEAN,
    is_mailing_paused BOOLEAN,
    ts_load TIMESTAMP
);

ALTER TABLE janus.fact_lead_task_contact_flows OWNER TO airflow;