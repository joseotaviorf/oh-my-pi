DROP TABLE IF EXISTS tickets.dim_repair_tickets;
CREATE TABLE IF NOT EXISTS tickets.dim_repair_tickets (
    sk_ticket BIGINT,
    responsible_budget VARCHAR (50),
    responsible_execution VARCHAR (50),
    payment_format VARCHAR (50),
    reason_budget_delay VARCHAR (100),
    reason_execution_delay VARCHAR (100),
    request_type VARCHAR (50),
    repair_type VARCHAR (70),
    internal_evaluation VARCHAR (50),
    occurrences VARCHAR (150),
    additional_repair VARCHAR (50),
    is_budget_visit_required BOOLEAN,
    is_service_guarantee BOOLEAN,
    dt_created DATE
);
ALTER TABLE tickets.dim_repair_tickets OWNER TO airflow;
