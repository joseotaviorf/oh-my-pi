SELECT
  CDID AS id_campaign,
  CDNUMOFERTA AS id_offer,
  CASE
      WHEN UPPER(CDFIELD) = "U1VLRPRCAG" THEN "Parcelas Vencidas"
      WHEN UPPER(CDFIELD) = "U1VLRPRCAVAG" THEN "Parcelas a Vencer"
      WHEN UPPER(CDFIELD) = "U1VLRPRMUAGR" THEN "Multa Parcelas"
      WHEN UPPER(CDFIELD) = "U1VLRMUREAG" THEN "Multa Residuais"
      WHEN UPPER(CDFIELD) = "U1VLRMUAG" THEN "Multa Acordo"
      WHEN UPPER(CDFIELD) = "U1VLRPRJUAG" THEN "Juros Parcelas"
      WHEN UPPER(CDFIELD) = "U1VLRJUREAG" THEN "Juros Residuais"
      WHEN UPPER(CDFIELD) = "U1VLRJUAG" THEN "Juros Acordo"
      WHEN UPPER(CDFIELD) = "U1VLCUSREAG" THEN "Custas Residuais"
      WHEN UPPER(CDFIELD) = "U1VLCUSTASAG" THEN "Custas Acordo"
      WHEN UPPER(CDFIELD) = "U1VLRHOREAG" THEN "Honorários Residuais"
      WHEN UPPER(CDFIELD) = "U1VLRDESPJUD" THEN "Despesas judiciais"
      ELSE CDFIELD
  END AS field_name,
  CDORVL AS amount_without_discount,
  CDDISCVL AS amount_with_discount,
  CDORVL - CDDISCVL AS discount,
  CDDISC AS discount_percentage,
  NOW() AS ts_load
FROM datalake_cyber_raw.tb_campanha_desc
