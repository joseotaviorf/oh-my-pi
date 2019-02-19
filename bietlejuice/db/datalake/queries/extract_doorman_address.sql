SELECT
  d.*,
  regexp_extract(regexp_replace(trim(work_address), '[,;\-\.]'), '\d+$') AS extracted_work_house_number,
  trim(regexp_replace(regexp_replace(work_address, regexp_extract(regexp_replace(trim(work_address), '[,;\-\.]'), '\d+$')), '[,;\-\.]')) || ', ' || regexp_extract(regexp_replace(trim(work_address), '[,;\-\.]'), '\d+$') || ' ' || work_city AS formatted_address
FROM datalake_clean.ods_dim_user_doorman AS d
JOIN datalake_clean.ods_dim_user AS u ON CAST(d.sk_user_affiliate AS varchar) = u.dados_afiliado_id
WHERE work_address IS NOT NULL AND work_city IS NOT NULL AND work_address != '' AND work_city != ''
  AND dadosafiliado_ativo = '1'
;
