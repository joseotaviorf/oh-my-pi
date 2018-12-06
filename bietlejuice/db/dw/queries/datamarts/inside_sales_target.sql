select
  canal,
  nome,
  id::float::bigint,
  opportunnity_target::float::bigint,
  listing_target::float::bigint,
  team_leader,
  team_leader_id::float::bigint,
  manager,
  manager_id::float::bigint
from datalake_raw.inside_sales_target