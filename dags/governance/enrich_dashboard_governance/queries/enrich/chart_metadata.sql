with metabase_last_view as (
  select
    id_model,
    max(ts_viewed) as ts_last_view
  from
    datalake_metabase_clean.view_log
  group by
    id_model
),
window_chart as (
  select
    RANK() over (
      partition by id
      order by
        ts_updated desc
    ) as row_number,
    chart.id as id_chart,
    chart.id_user_creator as id_owner,
    chart.id_database,
    chart.id_table,
    chart.id_collection,
    chart.name as title,
    chart.description,
    chart.display as type,
    chart.is_archived,
    chart.ts_updated
  from
    datalake_metabase_clean.report_card as chart
),
metabase_chart as (
  select
    chart.id_chart,
    chart.id_owner,
    chart.id_database,
    chart.id_table,
    chart.id_collection,
    chart.title,
    chart.description,
    chart.type,
    chart.is_archived,
    if(
      lv.id_model is not null,
      lv.ts_last_view,
      chart.ts_updated
    ) as ts_last_view
  from
    window_chart as chart
    left join metabase_last_view as lv on lv.id_model = chart.id_chart
  where
    chart.row_number = 1
),
metabase_database as (
  select
    id as id_database,
    name as name_database
  from
    datalake_metabase_clean.metabase_database
  where
    name = "all-data"
  group by
    id,
    name
),
metabase_table as (
  select
    id as id_table,
    id_database,
    name as name_table,
    schema as hive_schema
  from
    datalake_metabase_clean.metabase_table
  group by
    id,
    id_database,
    name,
    schema
),
metabase_user as (
  select
    id as id_user,
    email
  from
    datalake_metabase_clean.core_user
  group by
    id,
    email
),
non_personal_location_collection(
  select
    id as id_collection,
    name as name_collection
  from
    datalake_metabase_clean.collection
  where
    id_user_personal_owner is null
),
flaten_location_collection as (
  select
    id as id_collection,
    name as name_collection,
    location as location_collection,
    split(location, '/') as array_location,
    explode(split(location, '/')) as dir_collection
  from
    datalake_metabase_clean.collection
  where
    id_user_personal_owner is null
    and location != '/'
),
joined_location_collection as (
  select
    fc.id_collection,
    fc.name_collection,
    fc.array_location,
    fc.dir_collection,
    mc.name_collection as dir_name_collection
  from
    flaten_location_collection as fc
    join non_personal_location_collection as mc on fc.dir_collection = mc.id_collection
),
metabase_collection as (
  select
    id_collection,
    name_collection,
    array_location,
    concat_ws(
      "/",
      collect_list(dir_name_collection),
      name_collection
    ) as readable_location
  from
    joined_location_collection
  group by
    id_collection,
    name_collection,
    array_location
  union
  select
    id as id_collection,
    name as name_collection,
    null as array_location,
    name as readable_location
  from
    datalake_metabase_clean.collection
  where
    id_user_personal_owner is null
    and location = "/"
)
select
  "metabase" as platform,
  concat("/", metabase_collection.readable_location, "/") as chart_path,
  chart.id_chart as chart_id,
  chart.type,
  chart.title,
  chart.description as chart_description,
  chart.ts_last_view as last_view,
  concat(
    "https://metabase.quintoandar.com.br/card/",
    chart.id_chart
  ) as chart_url,
  if(
    chart.id_table is not null,
    concat(
      "hive.",
      metabase_table.hive_schema,
      ".",
      metabase_table.name_table
    ),
    null
  ) as dataset,
  metabase_user.email as ownership,
  case
    when is_archived is true then 'DEPRECATED'
    when datediff(current_timestamp(), chart.ts_last_view) > 90 then 'DEPRECATED'
    else 'ACTIVE'
  end as status,
  cast(null as string) as domain,
  current_timestamp() as ts_ingested,
  year(current_timestamp()) as year,
  month(current_timestamp()) as month,
  day(current_timestamp()) as day
from
  metabase_chart as chart
  join metabase_database on chart.id_database = metabase_database.id_database
  left join metabase_user on chart.id_owner = metabase_user.id_user
  left join metabase_table on chart.id_table = metabase_table.id_table
  left join metabase_collection on chart.id_collection = metabase_collection.id_collection