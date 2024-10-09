SELECT
    ACTYPE AS id_agreement_type,
    ACFIELD AS field_name,
    ACLABEL AS label,
    ACOP AS arithmetic_operator,
    ACLOADPOS AS accounting_order,
    ACMAXDISC1 AS max_discount_level_1,
    ACMAXDISC2 AS max_discount_level_2,
    ACMAXDISC3 AS max_discount_level_3,
    ACMAXDISC4 AS max_discount_level_4,
    ACMAXDISC5 AS max_discount_level_5,
    ACMAXDISC6 AS max_discount_level_6,
    NOW() AS ts_load
  FROM datalake_cyber_raw.agtpdsc
