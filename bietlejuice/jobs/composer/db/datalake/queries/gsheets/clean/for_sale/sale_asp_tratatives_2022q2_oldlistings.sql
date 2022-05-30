SELECT
  INT(NULLIF(id_house,'')) AS id_house,
  test_database AS asp_database,
  asp_responsavel,
  listing AS asp_list,
  FLOAT(NULLIF(preco, '')) AS sale_price_listing,
  FLOAT(NULLIF(preco_calculadora, '')) AS sale_price_calculator,
  status_contato AS status_contact,
  DATE(NULLIF(data_contato_efetivo,'')) AS dt_effective_contact,
  DATE(NULLIF(break_up_date,'')) AS dt_break_up
FROM
  datalake_gsheets_raw.sale_asp_tratatives_2022q2_oldlistings