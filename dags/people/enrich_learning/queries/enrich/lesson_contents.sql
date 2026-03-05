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
)
SELECT
  CAST(resource_elem.lesson_resource_id AS STRING) AS id_lesson_content,
  COALESCE(
    CAST(resource_elem.content_id AS STRING),
    CAST(resource_elem.id AS STRING)
  ) AS id_content,
  id_lesson,
  id_section,
  id_pathway,
  resource_elem.requirement AS requirement,
  resource_elem.note AS note,
  resource_elem.sequence AS sequence,
  (resource_elem.requirement = 'Required') AS is_required,
  NOW() AS ts_load
FROM
  resources_exploded
