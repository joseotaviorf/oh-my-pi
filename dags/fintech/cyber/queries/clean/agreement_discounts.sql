SELECT
    ADID AS id_agreement,
    CASE
        WHEN ACFIELD = "U1VLRPRCAG" THEN "Valor atualizado das parcelas vencidas selecionadas"
        WHEN ACFIELD = "U1VLRPRCAVAG" THEN "Valor das parcelas a vencer selecionadas"
        WHEN ACFIELD = "U1VLRPRMUAGR" THEN "Valor de multa das parcelas selecionadas"
        WHEN ACFIELD = "U1VLRPRJUAG" THEN "Valor de juros das parcelas selecionadas"
        ELSE ACFIELD
    END AS field,
    CASE
        WHEN ADFIELD = "U1VLRPRCAG" THEN "Valor atualizado das parcelas vencidas selecionadas"
        WHEN ADFIELD = "U1VLRPRCAVAG" THEN "Valor das parcelas a vencer selecionadas"
        WHEN ADFIELD = "U1VLRPRMUAGR" THEN "Valor de multa das parcelas selecionadas"
        WHEN ADFIELD = "U1VLRPRJUAG" THEN "Valor de juros das parcelas selecionadas"
        ELSE ADFIELD
    END AS field_name,
    ADOP AS arithmetic_operator,
    ADORVL AS amount_without_discount,
    ADDISCVL AS amount_with_discount,
    ADDISC AS discount,
    ADDISCT AS discount_percentage,
    NOW() AS ts_load
FROM datalake_cyber_raw.agdscdet
