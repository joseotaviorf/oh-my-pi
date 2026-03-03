WITH
exploded_sections AS (
  SELECT
    id AS id_pathway,
    EXPLODE(sections) AS section_elem
  FROM
    datalake_degreed_clean.pathway_details
  WHERE
    sections IS NOT NULL
    AND SIZE(sections) > 0
)
SELECT
  CAST(section_elem.section_id AS STRING) AS id_section,
  id_pathway,
  section_elem.title AS section_title,
  section_elem.description AS section_description,
  section_elem.sequence AS section_sequence,
  NOW() AS ts_load,
  TRANSFORM(
    COALESCE(section_elem.lessons, ARRAY()),
    l -> CAST(l.lesson_id AS STRING)
  ) AS lesson_ids,
  FLATTEN(
    TRANSFORM(
      COALESCE(section_elem.lessons, ARRAY()),
      l -> TRANSFORM(COALESCE(l.resources, ARRAY()),
      r -> CAST(r.content_id AS STRING))
    )
  ) AS content_ids
FROM
  exploded_sections
