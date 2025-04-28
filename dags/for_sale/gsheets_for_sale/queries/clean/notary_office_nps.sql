SELECT 
  sk_offer,
  metric_group,
  payment_method,
  score_category,
  comment,
  apoio_parceiros_cartorio AS support_partners_notary,
  apoio_name AS support_name,
  CASE
    WHEN Apoio_seguiu_com_parceiro = 'Sim' THEN true
    WHEN Apoio_seguiu_com_parceiro = 'Não' THEN false
    ELSE NULL
  END AS support_followed_with_partner,
  INT(score) AS score,
  to_date(dt_offer_compartilhada, 'dd/MM/yyyy') AS dt_offer_shared,
  to_date(ts_answered, 'dd/MM/yyyy') AS ts_answered,
  to_date(ts_sale_agreement_signed, 'd/M/yyyy') AS ts_sale_agreement_signed,
  NOW() AS ts_load
FROM 
  datalake_gsheets_raw.notary_office_nps