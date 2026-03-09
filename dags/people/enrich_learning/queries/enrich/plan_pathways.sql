WITH
sections_exploded AS (
  SELECT
    id AS id_plan,
    EXPLODE(COALESCE(sections, ARRAY())) AS section_elem
  FROM
    datalake_degreed_clean.skill_plan_details
  WHERE
    sections IS NOT NULL
    AND SIZE(sections) > 0
),
resources_exploded AS (
  SELECT
    id_plan,
    EXPLODE(COALESCE(section_elem.resources, ARRAY())) AS resource_elem
  FROM
    sections_exploded
),
pathway_resources AS (
  SELECT
    id_plan,
    CAST(resource_elem.id AS STRING) AS id_pathway
  FROM
    resources_exploded
  WHERE
    LOWER(TRIM(CAST(resource_elem.type AS STRING))) = 'pathway'
    AND resource_elem.id IS NOT NULL
)
SELECT DISTINCT
  id_plan,
  id_pathway,
  NOW() AS ts_load
FROM
  pathway_resources
