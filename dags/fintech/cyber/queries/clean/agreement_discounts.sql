SELECT
    CAST(ADID AS STRING) AS id_agreement,
    ACFIELD AS field,
    CASE
        WHEN UPPER(ADFIELD) = "U1VLRPRCAG" THEN "Parcelas Vencidas"
        WHEN UPPER(ADFIELD) = "U1VLRPRCAVAG" THEN "Parcelas a Vencer"
        WHEN UPPER(ADFIELD) = "U1VLRPRMUAGR" THEN "Multa Parcelas"
        WHEN UPPER(ADFIELD) = "U1VLRMUREAG" THEN "Multa Residuais"
        WHEN UPPER(ADFIELD) = "U1VLRMUAG" THEN "Multa Acordo"
        WHEN UPPER(ADFIELD) = "U1VLRPRJUAG" THEN "Juros Parcelas"
        WHEN UPPER(ADFIELD) = "U1VLRJUREAG" THEN "Juros Residuais"
        WHEN UPPER(ADFIELD) = "U1VLRJUAG" THEN "Juros Acordo"
        WHEN UPPER(ADFIELD) = "U1VLCUSREAG" THEN "Custas Residuais"
        WHEN UPPER(ADFIELD) = "U1VLCUSTASAG" THEN "Custas Acordo"
        WHEN UPPER(ADFIELD) = "U1VLRHOREAG" THEN "Honorários Residuais"
        WHEN UPPER(ADFIELD) = "U1VLRDESPJUD" THEN "Despesas judiciais"
        ELSE ADFIELD
    END AS field_name,
    ADOP AS arithmetic_operator,
    ADORVL AS amount_without_discount,
    ADDISCVL AS amount_with_discount,
    ADORVL - ADDISCVL AS discount,
    ADDISC AS discount_percentage_rounded,
    ADDISCT AS discount_percentage,
    NOW() AS ts_load
FROM datalake_cyber_raw.agdscdet
