with slots as (
  select
    pr.visit,
    s.slot
  from datalake_raw.planner_region pr
  cross join unnest(pr.schedules.slots) as s (slot)
  where pr.dt = '{date}'
    and pr.region = '{id_class}'
)
select
  visit,
  slot.available,
  slot.status,
  slot.available_agents,
  slot.id,
  slot.time
from slots
;