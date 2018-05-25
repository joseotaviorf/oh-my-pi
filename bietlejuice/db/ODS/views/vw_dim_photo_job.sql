drop view if exists vw_dim_photo_job;
create or replace view vw_dim_photo_job
as
with base_jobs as (
	select
		*,
		row_number() over (partition by imovel_id order by dt_job_created) as rn
	from
		public.photo_job
)
select
	j1.id as sk_photo_job,
	j1.id,
	j2.id,
	j1.imovel_id,
	j1.job_status,
	j1.creation_origin,
	j1.flexible_schedule,
	j1.dt_photographer_accepted,
	j1.dt_job_created,
	j1.dt_job_issued,
	j1.dt_shoot_started,
	j1.dt_job_scheduled,
	j1.dt_photos_uploaded,
	j1.dt_updated,
	j1.scheduling_instructions::varchar(100) as scheduling_instructions,
	j1.photo_shoot_contact_name,
	j1.photo_shoot_email,
	j1.photo_shoot_phone,
	j1.photo_shoot_second_phone,
	j1.approved,
	j1.confirmed,
	j1.lockbox,
	j1.key_withdraw,
	j1.key_comments::varchar(100) as key_comments,
	j1.photographer_id,
	j1.photographer_name,
	j1.photographer_email,
	j1.dt_photographer_start,
	j1.photographer_contract_type,
	j1.job_problem_reason,
	j1.cancel_reason::varchar(100) as cancel_reason,
	j1.user_cancel_dt,
	j1.user_cancel_id,
	j1.user_cancel_name,
	j1.user_cancel_email,
	(j2 is not null) rescheduled
from
	base_jobs j1
left join
	base_jobs j2
	on j1.imovel_id = j2.imovel_id
	and j1.rn = j2.rn -1
	and j1.dt_job_created + interval '30 day' > j2.dt_job_created;