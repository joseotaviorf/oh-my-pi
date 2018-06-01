-- DROP TABLE crm.lead_tasks

CREATE TABLE crm.lead_tasks (
	task_id varchar(255) NULL,
	task_status varchar(255) NULL,
	rep_id int4 NULL,
	lead_id int4 NULL,
	number_of_reschedules int4 NULL,
	first_rep_id int4 NULL,
	dt_created timestamp NULL,
	dt_closed timestamp NULL
)
WITH (
	OIDS=FALSE
) ;
CREATE INDEX dtx ON crm.lead_tasks USING btree (dt_created) ;
CREATE INDEX lead_idx ON crm.lead_tasks USING btree (lead_id) ;