SELECT 
  id,
  sale_id AS id_sale,
  error_type,
  incorrect_value,
  TIMESTAMP(solved_at) AS ts_solved,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_monopoly_raw.nota_fiscal_emission_error