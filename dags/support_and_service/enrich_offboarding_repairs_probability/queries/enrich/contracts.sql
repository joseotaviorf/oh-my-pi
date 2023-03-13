WITH booked_inspections AS (
  SELECT
    i.id_inspection AS sk_inspection,
    i.id_external AS sk_main_inspection,
    i.id_contract AS sk_contract,
    i.status,
    i.inspection_type,
    CAST(i.ts_created AS DATE) AS dt_booked
  FROM
    datalake_inspections.inspection_booking i
  WHERE
    i.inspection_type IN ('offboarding', 'verification')
    AND i.status != 'cancelled'
    AND CAST(i.ts_created AS DATE) = '{execution_date}'
),
booking_review AS (
  SELECT
    rf.sk_house_listing,
    COUNT(
      CASE
        WHEN br.painting IS NOT NULL
          OR br.cost_benefit IS NOT NULL
          OR br.conservation IS NOT NULL THEN 1
        ELSE NULL
      END
    ) AS house_qty_booking_review,
    ROUND(CAST(AVG(br.painting) AS FLOAT), 2) AS house_score_painting,
    ROUND(CAST(AVG(br.cost_benefit) AS FLOAT), 2) AS house_score_cost_benefit,
    ROUND(CAST(AVG(br.conservation) AS FLOAT), 2) AS house_score_conservation
  FROM
    dw_public.fact_listing_rent_flows AS rf
  LEFT JOIN
    dw_public.dim_tenant_booking_review AS br
      ON br.sk_tenant_booking_review = rf.sk_tenant_booking_review
  WHERE
    br.review_status = 'DONE'
    AND rf.sk_house_listing IS NOT NULL
  GROUP BY
    1
),
proponent_infos AS (
  SELECT
    id_proposal,
    COUNT(id) AS contract_qty_proponent,
    ROUND(CAST(AVG(monthly_income) AS FLOAT), 2) AS contract_avg_income,
    ROUND(CAST(AVG(boavista_score) AS FLOAT), 2) AS contract_avg_boavista,
    ROUND(CAST(AVG(serasa_score) AS FLOAT), 2) AS contract_avg_serasa
  FROM
    datalake_sorting_hat_clean.proponent
  WHERE
    id_proposal IS NOT NULL
    AND monthly_income > 500
  GROUP BY
    1
),
house_consideration_infos AS (
  SELECT
    sk_house_listing,
    COUNT(
      CASE
        WHEN flg_visit_performed = TRUE THEN 1
        ELSE NULL
      END
    ) AS house_qty_visit
  FROM
    dw_public.fact_listing_rent_flows
  GROUP BY
    1
),
onb_inspection_infos AS (
  SELECT DISTINCT
    i.id_inspection AS sk_inspection,
    i.id_external AS sk_main_inspection,
    i.id_contract AS sk_contract,
    i.status
  FROM
    datalake_inspections.inspection_booking i
  WHERE
    i.inspection_type = 'onboarding'
    AND i.status != 'cancelled'
  QUALIFY
    FIRST(i.ts_created) OVER(PARTITION BY i.id_external ORDER BY i.ts_created DESC) = i.ts_created
),
inspection_counts AS (
  SELECT
    i.id_external AS sk_inspection,
    COUNT(DISTINCT it.id_item_group) + COUNT(DISTINCT it2.id) AS contract_qty_inspection_itens,
    COUNT(DISTINCT ir.id_item) FILTER(WHERE ir.user_type = 'TENANT' AND ir.user_comment IS NOT NULL)
    + COUNT(it2.tenant_comment) AS tenant_qty_entry_comment
  FROM
    datalake_inspections.inspection_booking i
  LEFT JOIN
    datalake_inspections.item it
      ON it.id_inspection = i.id_inspection
      AND i.source = 'IS'
  LEFT JOIN
    datalake_inspections.item_review ir
      ON ir.id_item = it.id_item
  LEFT JOIN
    datalake_ebdb_clean.inspection_item it2
      ON it2.id_inspection = i.id_external
      AND i.source = 'PWA'
  GROUP BY 1, 2
),
onb_inspections AS (
  SELECT
    oii.sk_contract,
    contract_qty_inspection_itens,
    tenant_qty_entry_comment
  FROM
    onb_inspection_infos AS oii
  LEFT JOIN
    inspection_counts AS ic
      ON oii.sk_main_inspection = ic.sk_inspection
),
rent_flow AS (
  SELECT DISTINCT
    rf.sk_contract,
    rf.sk_house_listing,
    rf.sk_proposal,
    rf.sk_house_listing / 1000 AS sk_house,
    rf.sk_client sk_tenant,
    rf.sk_region
  FROM
    dw_public.fact_listing_rent_flows AS rf
  WHERE
    rf.sk_contract != -1
),
repair_request_count AS (
  SELECT
    id_contract AS sk_contract,
    COUNT(DISTINCT id) AS contract_qty_repair
  FROM
    datalake_repairs_clean.repair_request
  GROUP BY
    1
),
contracts AS (
  SELECT
    dc.sk_contract,
    dc.dt_start dt_started,
    dc.dt_entrance,
    dc.dt_intended_end,
    dc.dt_annulment,
    ct.dt_termination,
    COALESCE(ct.dt_termination, dc.dt_annulment, CAST('{execution_date}' AS DATE)) AS dt_stimated_finish,
    dc.status AS contract_status,
    ROUND(CAST(dc.rent AS FLOAT), 2) AS rent,
    CASE
      WHEN dc.is_contract_b2b THEN 1
      ELSE 0
    END AS contract_is_b2b,
    CASE
      WHEN dc.is_exit_inspection_opted_out THEN 1
      ELSE 0
    END AS is_exit_inspection_opted_out,
    ct.id_termination AS sk_termination,
    ct.has_repairs,
    ct.repair_resolution,
    ct.status AS termination_status,
    ct.repair_cost
  FROM
    dw_public.dim_contract AS dc
  LEFT JOIN
    datalake_offboarding.contract_termination AS ct
      ON dc.sk_contract = ct.id_contract
      AND ct.status = 'DONE'
  WHERE
    dc.country_code = 'BR'
    AND dc.status IN ('Ativo', 'Finalizado')
),
contract_people_qty AS (
  SELECT
    sk_contract,
    SUM(
      CASE
        WHEN contract_role = 'tenant' THEN 1
        ELSE 0
      END
    ) AS contract_qty_tenant,
    SUM(
      CASE
        WHEN contract_role = 'dweller' THEN 1
        ELSE 0
      END
    ) AS contract_qty_dweller
  FROM
    dw_quintoandar.fact_contract_people
  GROUP BY
    1
)
SELECT
  c.sk_contract AS id_contract,
  dr.city_name AS house_city,
  pi.contract_avg_income,
  pi.contract_avg_boavista,
  pi.contract_avg_serasa,
  COALESCE(DATEDIFF(c.dt_annulment, c.dt_entrance), DATEDIFF('{execution_date}', c.dt_entrance)) AS contract_ndays_started2annulment,
  oic.contract_qty_inspection_itens,
  pi.contract_qty_proponent,
  CAST(ROUND(c.rent / hl.house_total_area, 2) AS FLOAT) AS contract_rent_by_area,
  rrc.contract_qty_repair,
  c.rent AS contract_rent,
  CASE
    WHEN DATEDIFF(c.dt_termination, c.dt_entrance) <= 60 THEN 1
    ELSE 0
  END AS contract_was_too_early_terminated,
  c.contract_is_b2b,
  c.is_exit_inspection_opted_out,
  CASE
    WHEN la.armarios_no_quarto = 1
      OR la.armarios_no_banheiro = 1
      OR la.armarios_na_cozinha = 1 THEN 1
    ELSE 0
  END AS house_has_closet,
  CASE
    WHEN la.gas_encanado = 1
      OR la.chuveiro_a_gas = 1 THEN 1
    ELSE 0
  END AS house_has_gas_system,
  CASE
    WHEN la.tomadas_novas = 1 THEN 1
    ELSE 0
  END AS house_has_new_plug,
  CASE
    WHEN la.animais_de_estimacao = 1 THEN 1
    ELSE 0
  END AS house_is_pet_friendly,
  hci.house_qty_visit,
  br.house_qty_booking_review,
  br.house_score_painting,
  br.house_score_cost_benefit,
  br.house_score_conservation,
  ROUND(CAST(hl.house_total_area AS FLOAT), 2) AS house_total_area,
  oic.tenant_qty_entry_comment,
  bi.dt_booked,
  c.dt_started
FROM
  contracts AS c
JOIN
  booked_inspections AS bi
    ON c.sk_contract = bi.sk_contract
LEFT JOIN
  rent_flow AS rf
    ON c.sk_contract = rf.sk_contract
LEFT JOIN
  dw_public.dim_region AS dr
    ON rf.sk_region = dr.sk_region
LEFT JOIN
  dw_datamarts.dim_house_listing_amenities AS la
    ON CAST(rf.sk_house_listing / 1000 AS BIGINT) = CAST(la.id_house AS BIGINT)
LEFT JOIN
  dw_public.dim_house_listing AS hl
    ON rf.sk_house_listing = hl.sk_house_listing
LEFT JOIN
  proponent_infos AS pi
    ON rf.sk_proposal = pi.id_proposal
LEFT JOIN
  house_consideration_infos AS hci
    ON rf.sk_house_listing = hci.sk_house_listing
LEFT JOIN
  booking_review AS br
    ON rf.sk_house_listing = br.sk_house_listing
LEFT JOIN
  onb_inspections AS oic
    ON c.sk_contract = oic.sk_contract
LEFT JOIN
  repair_request_count AS rrc
    ON c.sk_contract = rrc.sk_contract
