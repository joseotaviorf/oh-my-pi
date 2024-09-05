with
metabase_last_view as (
  select
    id_model,
    count(id_model) as views,
    max(ts_viewed) as ts_last_view
  from
    datalake_metabase_clean.view_log
  where
    date(ts_viewed) <= date(format_string('%d-%d-%d', {year}, {month}, {day}))
  group by
    id_model
),
metabase_dashboard_last_update as (
  select
    RANK() over (
      partition by id
      order by
        ts_updated desc
    ) as row_number,
    CAST(md.id as STRING) as id_dashboard,
    md.id_user_creator as id_owner,
    md.id_collection,
    md.name as title,
    md.description,
    md.id_collection,
    md.is_archived
  from
    datalake_metabase_clean.report_dashboard md
  where
    date(ts_updated) <= date(format_string('%d-%d-%d', {year}, {month}, {day}))
),
metabase_dashboards as (
  select
    mdlu.id_dashboard,
    mdlu.id_owner,
    mdlu.id_collection,
    mdlu.title,
    mdlu.description,
    mdlu.is_archived,
    mdlu.id_collection
  from
    metabase_dashboard_last_update mdlu
  where
    mdlu.row_number == 1
),
metabase_user_last_update as (
  select
    RANK() over (
      partition by id
      order by
        ts_updated desc
    ) as row_number,
    id as id_user,
    email
  from
    datalake_metabase_clean.core_user
),
metabase_user as (
select
  mulu.id_user,
  mulu.email
from
  metabase_user_last_update mulu
where
  mulu.row_number == 1
),
metabase_collections_filtered as (
  select
    id as id_collection,
    name as name_collection,
    location
  from
    datalake_metabase_clean.collection
  where
    id_user_personal_owner is null
),
metabase_collections_exploded as (
  select
    id_collection,
    name_collection,
    explode(split(trim('/' from location), '/')) as dir_collection_id
  from
    metabase_collections_filtered
),
metabase_collections as (
  select
    mce.id_collection,
    mce.name_collection,
    concat_ws(
      "/",
      collect_list(mcf.name_collection),
      mce.name_collection
    ) as readable_location
  from
    metabase_collections_exploded as mce
    join metabase_collections_filtered as mcf on mce.dir_collection_id = mcf.id_collection
  group by mce.id_collection, mce.name_collection
),
metabase_dash_card as (
  select
    CAST(id_dashboard as STRING) as id_dashboard,
    collect_list(id_card) as ids_charts
  from
    datalake_metabase_clean.report_dashboard_card
  where
    id_card is not null and
    date(ts_updated) <= date(format_string('%d-%d-%d', {year}, {month}, {day}))
  group by
    id_dashboard
),
metabase_dashboard_enrich as (
    select
      "metabase" as platform,
      md.id_dashboard,
      mc.readable_location as dashboard_path,
      md.title,
      md.description,
      lv.views,
      mu.email as ownership,
      CASE
        WHEN mc.readable_location like 'Fintech%' THEN 'Fintech'
        WHEN mc.readable_location like 'Cross%' THEN 'Cross'
        WHEN mc.readable_location like 'For Rent%' THEN 'For Rent'
        WHEN mc.readable_location like 'For Sale%' THEN 'For Sale'
        WHEN mc.readable_location like 'Growth%' THEN 'Growth'
        WHEN mc.readable_location like 'International%' THEN 'International'
        WHEN mc.readable_location like 'Rede%' THEN 'Rede'
        WHEN mc.readable_location like 'BedRock%' THEN 'BedRock'
        WHEN mc.readable_location like 'Tech Platform%' THEN 'Tech Platform'
        WHEN mc.readable_location like 'Support and Services%' THEN 'Support and Services'
        WHEN mc.readable_location like 'People%' THEN 'People'
        ELSE Null
      END as domain,
      case
        when md.is_archived is true then 'DEPRECATED'
        when datediff(date(format_string('%d-%d-%d', {year}, {month}, {day})), lv.ts_last_view) > 90 then 'DEPRECATED'
        else 'ACTIVE'
      end as status,
      mdc.ids_charts,
      lv.ts_last_view as last_view,
      concat(
        "https://metabase.quintoandar.com.br/dashboard/",
        md.id_dashboard
      ) as dashboard_url,
      date(format_string('%d-%d-%d', {year}, {month}, {day})) as dt_updated,
      {year} as year,
      {month} as month,
      {day} as day
    from
      metabase_dashboards md
      join metabase_user mu on mu.id_user = md.id_owner
      join metabase_dash_card mdc on mdc.id_dashboard = md.id_dashboard
      join metabase_last_view lv on lv.id_model = md.id_dashboard
      join metabase_collections mc on md.id_collection = mc.id_collection
)
select
  platform,
  id_dashboard,
  dashboard_path,
  title,
  description,
  views,
  ownership,
  domain,
  status,
  ids_charts,
  last_view,
  dashboard_url,
  dt_updated,
  year,
  month,
  day
from metabase_dashboard_enrich
