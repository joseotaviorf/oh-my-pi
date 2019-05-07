with tickets as (
	select distinct t.* from datalake_clean.zendesk_tickets t
	where (t.channel<>'api' or (t.channel='api' and t.tags not like '%hsm%')) and (t.subject != 'SCRUBBED')
	and dt_extraction='{execution_date}'
)
select count(*) from tickets