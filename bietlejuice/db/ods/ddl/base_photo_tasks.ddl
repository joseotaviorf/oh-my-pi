drop table public.base_photo_tasks;
create table public.base_photo_tasks (
  house_id integer,
  has_job_photo boolean,
  has_fup_photo boolean
);

CREATE INDEX bpt_house_id_idx ON public.base_photo_tasks USING btree (house_id);
