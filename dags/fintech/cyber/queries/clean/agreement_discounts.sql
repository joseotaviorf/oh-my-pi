SELECT
    ADID AS id_agreement,
    ACFIELD AS field,
    CASE
        WHEN UPPER(ADFIELD) = "U1VLRPRCAG" THEN "Valor principal das parcelas vencidas selecionadas"
        WHEN UPPER(ADFIELD) = "U1VLRPRCAVAG" THEN "Valor principal das parcelas a vencer selecionadas"
        WHEN UPPER(ADFIELD) = "U1VLRPRMUAGR" THEN "Valor de multa das parcelas selecionadas"
        WHEN UPPER(ADFIELD) = "U1VLRPRJUAG" THEN "Valor de juros das parcelas selecionadas"
        WHEN UPPER(ADFIELD) = "U1VLRMUREAG" THEN "Valor de multa residual das parcelas selecionadas"
        WHEN UPPER(ADFIELD) = "U1VLRMUAG" THEN "Valor da Multa para Acordo (Visão Contrato)"
        WHEN UPPER(ADFIELD) = "U1VLRJUREAG" THEN "Valor de juros residuais das parcelas selecionadas"
        WHEN UPPER(ADFIELD) = "U1VLRJUAG" THEN "Valor dos Juros para Acordo (Visão Contrato)"
        WHEN UPPER(ADFIELD) = "U1VLCUSREAG" THEN "Valor das Custas Residuais das parcelas selecionadas"
        WHEN UPPER(ADFIELD) = "U1VLCUSTASAG" THEN "Valor das Custas (Visão Contrato)"
        WHEN UPPER(ADFIELD) = "U1VLRHOREAG" THEN "Valor dos Honorários Residuais das parcelas selecionadas"
        WHEN UPPER(ADFIELD) = "U1VLRDESPJUD" THEN "Valor das despesas judiciais"
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
