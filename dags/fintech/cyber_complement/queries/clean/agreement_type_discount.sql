SELECT
    ACTYPE AS agreement_type,
    ACFIELD AS original_field_name,
    CASE
      WHEN ACFIELD = "dmamtdlq" THEN "overdue_amount"
      WHEN ACFIELD = "dmamtdlq" THEN "overdue_amount"
    END AS datalake_field_name,
    ACLABEL AS label,
    ACOP AS arithmetic_operator,
    ACLOADPOS AS discount_batch_position,
    ACMAXDISC1 AS max_discount_1,
    ACMAXDISC2 AS max_discount_2,
    ACMAXDISC3 AS max_discount_3,
    ACMAXDISC4 AS max_discount_4,
    ACMAXDISC5 AS max_discount_5,
    ACMAXDISC6 AS max_discount_6
  FROM datalake_cyber_raw.agtpdsc
