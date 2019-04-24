WITH doorman_address AS (
  SELECT
    d.*,
    regexp_extract(regexp_replace(trim(work_address), '[,;\-\.]'), '\d+$') AS extracted_work_house_number,
    trim(regexp_replace(regexp_replace(work_address, regexp_extract(regexp_replace(trim(work_address), '[,;\-\.]'), '\d+$')), '[,;\-\.]')) || ', ' || regexp_extract(regexp_replace(trim(work_address), '[,;\-\.]'), '\d+$') || ' ' || work_city AS formatted_address,
    a.google_formatted_address
  FROM datalake_clean.ods_dim_user_doorman AS d
  JOIN datalake_clean.ods_dim_user AS u ON CAST(d.sk_user_affiliate AS varchar) = u.dados_afiliado_id
  LEFT JOIN datalake_raw.doorman_geocoded_addresses AS a ON d.id_user_doorman = a.id_user_doorman
  WHERE
    dadosafiliado_ativo = '1'
    AND COALESCE(work_address, '') != ''
    AND COALESCE(work_city, '') != ''
    AND COALESCE(work_lat, '') = ''
    AND COALESCE(work_lng, '') = ''
)
SELECT *
FROM doorman_address
WHERE extracted_work_house_number IS NOT NULL
  AND formatted_address IS NOT NULL
;
