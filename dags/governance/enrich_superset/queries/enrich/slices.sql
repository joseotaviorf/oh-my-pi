with last_slice AS (
  SELECT
    *,
    regexp_extract(slice_name,'\\[(Bedrock|Cross|Data Ops \\& Governance|Fintech|For Brokers|For Rent|For Sale|Growth|Internacional|MLOps|Rede|Support and Services)\\]') company_line,
    RANK() OVER (PARTITION BY id ORDER BY ts_changed DESC) most_recent_rank 
  FROM datalake_superset_clean.slices
), slice_owners AS (
  SELECT 
    su.id_slice,
    COLLECT_SET(u.email) as owners_email
  from datalake_superset_clean.slice_user su
  join datalake_superset.ab_user u ON u.id = su.id_user
  GROUP BY 1
), logs as (
  select 
    id_slice,
    count(0) last_90d_views
  FROM datalake_superset_clean.logs
  WHERE id_slice IS NOT NULL
    AND action = 'ChartDataRestApi.data' 
    AND ts_event > CURRENT_DATE - interval '90' day
  GROUP BY 1
), tags AS (
  SELECT 
      tog.id_object,
      collect_set(t.tag_name) AS tags
  FROM datalake_superset.tagged_object tog
  JOIN datalake_superset.tag t on t.id = `tog`.`id_tag`
  WHERE object_type = 'slice'
  GROUP BY 1
)
SELECT
  ls.id, 
  ls.slice_name,
  ls.viz_type,
  ls.description,
  ls.id_datasource, 
  sow.owners_email AS business_owners,
  u_creator.email AS technical_owner,
  u_changed.email AS last_owner,
  ls.certified_by, 
  ls.ts_created,
  ls.ts_changed,
  ls.company_line,
  "superset" AS platform,
  IF(l.id_slice IS NOT NULL, 'Ativo', 'Deprecado') AS entity_status,
  COALESCE(l.last_90d_views,0) AS last_90d_views,
  array_remove(regexp_extract_all(ls.slice_name, '\\[([^\\]]+)\\]'), ls.company_line) AS tags,
  tags.tags AS new_tags,
  CONCAT("https://superset.data.quintoandar.com.br/explore/?slice_id=", ls.id) as chart_url
FROM last_slice ls
JOIN datalake_superset.ab_user u_creator ON u_creator.id = ls.id_user_created
JOIN datalake_superset.ab_user u_changed ON u_changed.id = ls.id_user_changed
JOIN slice_owners sow ON sow.id_slice = ls.id 
LEFT JOIN logs l on l.id_slice = ls.id
LEFT JOIN tags ON tags.id_object = ls.id