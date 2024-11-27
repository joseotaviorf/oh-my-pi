SELECT
    acct_grp AS group,
    level1 AS level,
    test,
    sequence,
    comment1 AS comment,
    LOWER(field_1) AS field_1,
    CASE
      WHEN LOWER(op) = '.eq.' THEN '='
      WHEN LOWER(op) = '.ge.' THEN '>='
      WHEN LOWER(op) = '.gt.' THEN '>'
      WHEN LOWER(op) = '.le.' THEN '<='
      WHEN LOWER(op) = '.lt.' THEN '<'
      WHEN LOWER(op) = '.ne.' THEN '!='
      ELSE LOWER(op)
    END AS operator,
    LOWER(field_2) AS field_2,
    LOWER(field_2_flag) AS field_2_flag,
    LOWER(field_3) AS field_3,
    LOWER(field_3_flag) AS field_3_flag,
    or_flag,
    num_return,
    next_level,
    nxt_return,
    queue,
    NOW() AS ts_load
  FROM datalake_cyber_raw.lbl_dectbl5
