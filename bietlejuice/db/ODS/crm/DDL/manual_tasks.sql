drop table crm.manual_tasks;

CREATE TABLE crm.manual_tasks (
	id_task varchar(255) NULL,
	id_task_opener int4 NULL,
	id_assignee int4 NULL,
	id_original_assignee varchar(255) NULL,
	id_workgroup varchar(255) NULL,
	task_done boolean NULL,
	description varchar(255) NULL,
	subject varchar(255) NULL,
	sk_date_created int8 NULL,
	dt_created timestamp NULL,
	dt_reschedule timestamp NULL,
	dt_closed timestamp NULL
)
