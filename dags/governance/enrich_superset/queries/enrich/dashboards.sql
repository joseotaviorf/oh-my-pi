WITH last_dash AS (
  SELECT  
    *, 
    regexp_extract(d.dashboard_title,'\\[(Bedrock|Cross|Data Ops \\& Governance|Fintech|For Brokers|For Rent|For Sale|Growth|Internacional|MLOps|Rede|Support and Services)\\]') AS company_line,
    RANK() OVER (PARTITION BY id ORDER BY ts_changed DESC) most_recent_rank
  FROM datalake_superset_clean.dashboards d 
), slices_list AS (
  SELECT 
     id_dashboard,
     collect_set(id_slice) AS ids_slice
  FROM datalake_superset_clean.dashboard_slices
  GROUP BY 1
), dash_owners AS (
  SELECT 
    du.id_dashboard,
    collect_set(u.email) AS owners_email
  FROM datalake_superset_clean.dashboard_user du
  JOIN datalake_superset.ab_user u ON u.id = du.id_user
  GROUP BY 1
), logs AS (
  SELECT 
    id_dashboard,
    COUNT(0) last_90d_views
  FROM datalake_superset_clean.logs
  WHERE id_dashboard IS NOT NULL 
    AND action = 'DashboardRestApi.get' 
    AND ts_event > CURRENT_DATE - interval '90' day
  GROUP BY 1
), tags AS (
  SELECT 
      tog.id_object,
      collect_set(t.tag_name) AS tags
  FROM datalake_superset.tagged_object tog
  JOIN datalake_superset.tag t on t.id = `tog`.`id_tag`
  WHERE tog.object_type = 'dashboard'
  GROUP BY 1
), txt_boxes AS (
  SELECT
    id,
    ts_changed, 
    EXPLODE(FROM_JSON(position_json,'MAP<string,string>') )
  FROM last_dash
  WHERE most_recent_rank = 1
), descr AS (
  SELECT 
  id,
  `value`:meta.code AS entity_description,
  RANK() OVER (PARTITION BY id ORDER BY ts_changed DESC) most_recent_txt_rank
  FROM txt_boxes 
  WHERE `key` LIKE 'MARKDOWN-%' AND LOWER(`value`:meta.code) LIKE '%description%' AND CHAR_LENGTH(`value`:meta.code) > 60 -- this also filters published
)
SELECT 
  d.id,
  d.dashboard_title AS entity_name,
  CONCAT('https://superset.data.quintoandar.com.br/superset/dashboard/', CAST(d.id AS string))  AS entity_url,
  u_creator.email AS technical_owner,
  u_changed.email AS last_owner,
  dw.owners_email AS business_owners,
  d.company_line,
  array_remove(regexp_extract_all(d.dashboard_title, '\\[([^\\]]+)\\]'), d.company_line) tags,
  sl.ids_slice AS lineage_charts,
  ds.entity_description,
  "superset" AS platform,
  d.certified_by,
  IF(l.id_dashboard IS NOT NULL, 'Ativo', 'Deprecado') AS entity_status,
  d.ts_created,
  d.ts_changed, 
  COALESCE(l.last_90d_views,0) AS last_90d_views,
  tags.tags AS new_tags,
  d.published
FROM last_dash d 
JOIN slices_list sl ON sl.id_dashboard = d.id
JOIN dash_owners dw ON dw.id_dashboard = d.id
JOIN datalake_superset.ab_user u_creator ON u_creator.id = d.id_user_created
JOIN datalake_superset.ab_user u_changed ON u_changed.id = d.id_user_changed
LEFT JOIN descr ds ON ds.id = d.id AND ds.most_recent_txt_rank = 1
LEFT JOIN logs l ON l.id_dashboard = d.id
LEFT JOIN tags ON tags.id_object = d.id
WHERE d.most_recent_rank = 1