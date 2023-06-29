SELECT
  INT(NULLIF(id_house,'')) AS id_house,
  test_database AS asp_database,
  listings AS asp_list,
  group_ab,
  NULLIF(finalID,'') AS id_pair_match
FROM
  datalake_gsheets_raw.sale_asp_groupsab_2022q2