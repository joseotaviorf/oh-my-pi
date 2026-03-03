WITH
sections_exploded AS (
  SELECT
    id AS id_pathway,
    EXPLODE(sections) AS section_elem
  FROM
    datalake_degreed_clean.pathway_details
  WHERE
    sections IS NOT NULL
    AND SIZE(sections) > 0
),
lessons_exploded AS (
  SELECT
    id_pathway,
    CAST(section_elem.section_id AS STRING) AS id_section,
    EXPLODE(COALESCE(section_elem.lessons, ARRAY())) AS lesson_elem
  FROM
    sections_exploded
),
resources_exploded AS (
  SELECT
    id_pathway,
    id_section,
    CAST(lesson_elem.lesson_id AS STRING) AS id_lesson,
    EXPLODE(COALESCE(lesson_elem.resources, ARRAY())) AS resource_elem
  FROM
    lessons_exploded
),
contents_rows AS (
  SELECT
    COALESCE(
      CAST(resource_elem.content_id AS STRING),
      CAST(resource_elem.id AS STRING)
    ) AS id_content,
    resource_elem.title AS title,
    resource_elem.description AS description,
    resource_elem.type AS resource_type
  FROM
    resources_exploded
)
SELECT
  id_content,
  MAX(title) AS title,
  MAX(description) AS description,
  MAX(resource_type) AS resource_type,
  NOW() AS ts_load
FROM
  contents_rows
GROUP BY
  id_content
