alter table {0}.planner_{1}
  add if not exists partition (dt='{2}', {1}='{3}')
  location 's3://{4}/{5}/planner/dt={2}/{1}={3}'
;