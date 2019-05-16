DROP TABLE IF EXISTS crm.photo_tasks;
CREATE TABLE crm.photo_tasks (
  	task_id varchar(255),
	task_status varchar(255),
	rep_id integer,
	first_rep_id integer,
	photo_job_id integer,
	number_of_reschedules integer,
	dt_created timestamp,
	dt_closed timestamp
);