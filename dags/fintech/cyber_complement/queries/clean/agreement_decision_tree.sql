SELECT
    acct_grp AS group,
    level1 AS level,
    test,
    sequence,
    comment1 AS comment,
    LOWER(field_1) AS field_1,
    CASE
      WHEN op = '.eq.' THEN '='
      WHEN op = '.ge.' THEN '>='
      WHEN op = '.gt.' THEN '>'
      WHEN op = '.le.' THEN '<='
      WHEN op = '.lt.' THEN '<'
      WHEN op = '.ne.' THEN '!='
      ELSE op
    END AS operator,
    LOWER(field_2) AS field_2,
    LOWER(field_2_flag) AS field_2_flag,
    LOWER(field_3) AS field_3,
    LOWER(field_3_flag) AS field_3_flag,
    or_flag,
    num_return,
    next_level,
    nxt_return,
    queue
  FROM datalake_cyber_raw.que_dectbl3
