with metabase_last_view as (
  select
    id_model,
    max(ts_viewed) as ts_last_view
  from
    datalake_metabase_clean.view_log
  group by
    id_model
),
window_dashboard as (
  select
    RANK() over (
      partition by id
      order by
        ts_updated desc
    ) as row_number,
    md.id as id_dashboard,
    md.id_user_creator as id_owner,
    md.id_collection,
    md.name as title,
    md.description as description_dashboard,
    md.id_collection,
    md.is_archived
  from
    datalake_metabase_clean.report_dashboard as md
),
metabase_dashboard as (
  select
    md.id_dashboard,
    md.id_owner,
    md.id_collection,
    md.title,
    md.description_dashboard,
    md.id_collection,
    md.is_archived,
    lv.ts_last_view
  from
    window_dashboard as md
    join metabase_last_view as lv on lv.id_model = md.id_dashboard
  where
    md.row_number = 1
),
metabase_chart as (
  select
    RANK() over (
      partition by id
      order by
        ts_updated desc
    ) as row_number,
    id as id_card,
    name as name_card
  from
    datalake_metabase_clean.report_card
),
metabase_dash_card as (
  select
    id_card,
    id_dashboard
  from
    datalake_metabase_clean.report_dashboard_card
  where
    id_card is not null
  group by
    id_card,
    id_dashboard
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
  dashboard.id_dashboard as dashboard_id,
  concat("/", metabase_collection.readable_location, "/") as dashboard_path,
  dashboard.title,
  dashboard.description_dashboard,
  dashboard.ts_last_view as last_view,
  concat(
    "https://metabase.quintoandar.com.br/dashboard/",
    dashboard.id_dashboard
  ) as dashboard_url,
  chart.id_card,
  chart.name_card as chart,
  metabase_user.email as ownership,
  case
    when dashboard.is_archived is true then 'DEPRECATED'
    when datediff(current_timestamp(), dashboard.ts_last_view) > 90 then 'DEPRECATED'
    else 'ACTIVE'
  end as status,
  cast(null as string) as domain,
  current_timestamp() as ts_ingested,
  year(current_timestamp()) as year,
  month(current_timestamp()) as month,
  day(current_timestamp()) as day
from
  metabase_dash_card as dc
  join metabase_dashboard as dashboard on dc.id_dashboard = dashboard.id_dashboard
  join metabase_chart as chart on dc.id_card = chart.id_card
  join metabase_user on metabase_user.id_user = dashboard.id_owner
  left join metabase_collection on dashboard.id_collection = metabase_collection.id_collection
where
  chart.row_number = 1