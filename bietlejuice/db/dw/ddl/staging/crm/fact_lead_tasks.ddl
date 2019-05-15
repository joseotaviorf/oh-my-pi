drop table if exists staging.fact_lead_tasks;
create table if not exists staging.fact_lead_tasks (
    sk_task varchar,
	sk_lead integer,
	is_closed boolean,
	sk_created_date integer,
	sk_first_realized_date integer,
	sk_first_resolved_date integer,
	sk_user_first_assignee integer,
	sk_user_first_resolver integer
);
