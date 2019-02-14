DROP TABLE IF EXISTS crm.manual_tasks;
CREATE TABLE crm.manual_tasks (
	id_task varchar(255),
	id_task_opener integer,
	id_assignee integer,
	id_original_assignee integer,
	id_workgroup varchar(255),
	task_done boolean,
	description varchar(255),
	subject varchar(255),
	sk_date_created bigint,
	dt_created timestamp,
	dt_reschedule timestamp,
	dt_closed timestamp
);