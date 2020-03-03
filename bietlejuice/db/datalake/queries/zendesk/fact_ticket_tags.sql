with tickets_filter as (
	select distinct * from datalake_clean.zendesk_tickets t
	where (t.ticket_via<>'api' or (t.ticket_via='api' and t.tags not like '%hsm%'))
  and dt_extracted = '{execution_date}'
)
SELECT
  distinct tf.id_ticket as sk_ticket,
  replace(replace(t.tag, '[', ''), ']', '') as ticket_tag,
  cast(tf.ts_updated as timestamp with time zone) as ts_updated,
  now() as ts_load
from tickets_filter tf
CROSS JOIN UNNEST(SPLIT(tf.tags,',')) AS t (tag)