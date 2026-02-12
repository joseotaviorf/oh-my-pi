SELECT
  id,
  pt_br,
  en_us,
  deprecated AS is_deprecated,
  created_at AS ts_created
FROM
  datalake_zordon_raw.culture_principles
