DROP TABLE public.potential_listings_lead_tasks;
CREATE TABLE public.potential_listings_lead_tasks (
	id int8 NULL,
	sk_user_sales_rep int4 NULL,
	sk_user_first_task_assignee int4 NULL,
	sk_user_last_task_assignee int4 NULL,
	sk_first_task_created_date int4 NULL,
	sk_first_task_closed_date int4 NULL,
	sk_last_task_created_date int4 NULL,
	sk_last_task_closed_date int4 NULL,
	first_isales_intervention text NULL,
	has_isales_intervention bool NULL,
	has_fup_photo_task bool NULL
);

CREATE INDEX pot_list_lead_tasks_id_idx ON public.potential_listings_lead_tasks USING btree (id);