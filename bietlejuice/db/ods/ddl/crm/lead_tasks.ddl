DROP TABLE IF EXISTS crm.lead_tasks;
CREATE TABLE crm.lead_tasks (
  	task_id varchar(255),
	task_status varchar(255),
	rep_id integer,
	first_rep_id integer,
	lead_id integer,
	number_of_reschedules integer,
	dt_created timestamp,
	dt_closed timestamp,
	task_type varchar(64)
);

create index lead_tasks_lead_id_idx on crm.lead_tasks (lead_id);
create index lead_tasks_dt_created_idx on crm.lead_tasks (dt_created);
