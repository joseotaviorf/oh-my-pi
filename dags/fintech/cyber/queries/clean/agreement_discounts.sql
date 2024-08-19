SELECT
    ADID AS id_negotiation,
    ACFIELD AS field_name,
    ADOP AS arithmetic_operator,
    ADORVL AS amount,
    ADDISC AS discount,
    ADDISCVL AS amount_with_discount,
    ADFIELD,
    ADDISCT,
    ADMIGRACAO
FROM datalake_cyber_raw.agdscdet
