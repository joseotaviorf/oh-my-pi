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
)
SELECT
  CAST(lesson_elem.lesson_id AS STRING) AS id_lesson,
  id_section,
  id_pathway,
  lesson_elem.title AS lesson_title,
  lesson_elem.description AS lesson_description,
  lesson_elem.sequence AS lesson_sequence,
  NOW() AS ts_load,
  TRANSFORM(
    COALESCE(lesson_elem.resources, ARRAY()),
    r -> CAST(r.content_id AS STRING)
  ) AS content_ids
FROM
  lessons_exploded
