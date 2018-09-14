select
  sk_visit_task,
  sk_demand,
  getdate() as dt_timestamp
from staging.bdg_crmvisit_demand
;