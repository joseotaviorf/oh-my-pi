drop table if exists datalake_raw.planner_region;
create external table if not exists datalake_raw.planner_region (
  visit struct<
    max_visits_per_pool: string,
    properties: array<
      struct<
        position: string,
        id: string
      >
    >,
    size: string
  >,
  schedules struct<
    slots: array<
      struct<
        available: string,
        status: string,
        available_agents: array<string>,
        id: string,
        time: string
      >
    >
  >
)
partitioned by (
  dt string,
  region string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
	'ignore.malformed.json' = 'true',
	'mapping.max_visits_per_pool' = 'MaxVisitsPerPool',
    'mapping.available_agents' = 'availableAgents'

)
location 's3://5a-datalake/raw/planner/'
;