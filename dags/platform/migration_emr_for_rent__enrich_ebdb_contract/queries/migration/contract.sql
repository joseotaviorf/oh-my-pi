WITH max_cancellation AS (
  SELECT
    id_contract,
    MAX(rev) AS max_rev
  FROM datalake_ebdb_clean.contract_aud
  WHERE
    mod_status AND status = 'Cancelado'
  GROUP BY
    1
), contract_cancellation_reason AS (
  SELECT
    mc.id_contract,
    CASE
      WHEN ure.reason RLIKE 'Desacordo entre as partes com rela..o a data de vig.ncia'
      THEN 'VALIDITY_DATES'
      WHEN ure.reason RLIKE 'N.o foi poss.vel contactar uma das partes'
      THEN 'UNREACHABLE'
      WHEN ure.reason RLIKE 'Prazo de assinatura expirado'
      THEN 'SIG_DEADLINE_EXPIRED'
      WHEN ure.reason RLIKE 'Inquilino alugou im.vel por fora do 5A'
      THEN 'TENANT_RENTING_WITH_OTHER_COMPANY'
      WHEN ure.reason RLIKE 'Propriet.rio alugou im.vel por fora do 5A'
      THEN 'OWNER_RENTING_WITH_OTHER_COMPANY'
      WHEN ure.reason RLIKE 'Inquilino prefere outro im.vel 5A'
      THEN 'TENANT_PREFERS_OTHER'
      WHEN ure.reason RLIKE 'Propriet.rio prefere outro inquilino 5A'
      THEN 'OWNER_PREFERS_OTHER'
      WHEN ure.reason RLIKE 'Caracter.sticas/informa..es incorretas no an.ncio'
      THEN 'INCORRECT_INFO'
      WHEN ure.reason RLIKE 'Desacordo entre as partes durante negocia..o'
      THEN 'DISAGREEMENT'
      WHEN ure.reason RLIKE 'Inquilino n.o concorda com modelo 5A'
      THEN 'TENANT_DOESNT_AGREE'
      WHEN ure.reason RLIKE 'Propriet.rio n.o concorda com modelo 5A'
      THEN 'OWNER_DOESNT_AGREE'
      WHEN ure.reason RLIKE 'Demora/confus.o durante processo 5A por parte do inquilino'
      THEN 'TENANT_DELAY'
      WHEN ure.reason RLIKE 'Demora/confus.o durante o processo 5A por parte do propriet.rio'
      THEN 'OWNER_DELAY'
      WHEN ure.reason RLIKE 'Houve uma altera..o no valor do im.vel'
      THEN 'PRICE_MODIFICATION'
      WHEN ure.reason RLIKE 'Inquilino comprou um im.vel e desistiu da loca..o'
      THEN 'TENANT_BUYING_HOUSE'
      WHEN ure.reason RLIKE 'Propriet.rio vendeu o im.vel e desistiu da loca..o'
      THEN 'OWNER_SELLING_HOUSE'
      WHEN ure.reason RLIKE 'Inquilino desistiu da loca..o devido a mudan.a ou problema familiar'
      THEN 'TENANT_GAVE_UP_RENTING'
      WHEN ure.reason RLIKE 'Propriet.rio desistiu da loca..o devido a mudan.a ou problema familiar'
      THEN 'OWNER_GAVE_UP_RENTING'
      WHEN ure.reason RLIKE 'Inquilino n.o conseguiu entregar/sair do im.vel atual'
      THEN 'TENANT_UNABLE_TO_LEAVE'
      WHEN ure.reason RLIKE 'Propriet.rio n.o conseguiu entregar/sair do im.vel'
      THEN 'OWNER_UNABLE_TO_LEAVE'
      ELSE 'OTHERS'
    END AS cancellation_reason,
    FROM_UNIXTIME(ure.ts_revision / 1000) AS ts_canceled
  FROM max_cancellation AS mc
  JOIN datalake_ebdb_clean.user_revision_entity AS ure
    ON ure.id = mc.max_rev
), contract_terminations AS (
  SELECT
    c_aud.id_contract,
    c_aud.id_house,
    c_aud.rev,
    ROW_NUMBER() OVER (PARTITION BY c_aud.id_contract ORDER BY ure.ts_revision) AS row_number,
    c_aud.mod_dt_termination,
    c_aud.dt_termination,
    LAG(c_aud.dt_termination) OVER (PARTITION BY c_aud.id_contract ORDER BY c_aud.rev) AS dt_previous_termination,
    FROM_UNIXTIME(ure.ts_revision / 1000) AS ts_revision
  FROM datalake_ebdb_clean.contract_aud AS c_aud
  JOIN datalake_ebdb_clean.user_revision_entity AS ure
    ON ure.id = c_aud.rev
  WHERE
    c_aud.mod_dt_termination
), contract_analyst_annulment_date AS (
  SELECT
    ct.id_contract,
    COALESCE(ct.ts_revision, ct.dt_termination) AS ts_analyst_annulment_input
  FROM contract_terminations AS ct
  WHERE
    ct.row_number = 1
), terminations AS (
  SELECT
    id_contract,
    status,
    dt_vacancy,
    dt_termination_finished
  FROM (
    SELECT
      id_contract,
      status,
      dt_vacancy,
      IF(status = 'DONE', CAST(ts_updated AS DATE), NULL) AS dt_termination_finished,
      ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY ts_created DESC) AS _w,
      ts_created
    FROM datalake_terminator_clean.termination
  ) AS _t
  WHERE
    _w = 1
), contract_metrics AS (
  SELECT
    id AS id_contract,
    status IN ('Minuta', 'PreAssinaturas') AS is_waiting_to_be_signed,
    status IN ('Ativo', 'Finalizado') AS is_active_or_ended,
    status = 'Ativo' AS is_active,
    status = 'Cancelado' AS is_canceled,
    status = 'Finalizado' AS is_ended,
    type = 'FullService' AS is_full_service,
    type = 'DealOnly' AS is_deal_only
  FROM datalake_ebdb_clean.contract
), ongoing_contracts AS (
  SELECT
    c.id AS id_contract,
    CASE
      WHEN cm.is_active
      AND NOT cm.is_deal_only
      AND CURRENT_DATE >= CAST(COALESCE(c.ts_signed, c.dt_started, c.dt_entered) AS DATE)
      AND (
        CURRENT_DATE < IF(
          t.status = 'DONE' AND c.dt_termination > CAST('2020-01-07' AS DATE),
          t.dt_vacancy,
          c.dt_termination
        )
        OR c.dt_termination IS NULL
      )
      THEN TRUE
      ELSE FALSE
    END AS is_ongoing_contract
  FROM datalake_ebdb_clean.contract AS c
  JOIN contract_metrics AS cm
    ON cm.id_contract = c.id
  LEFT JOIN terminations AS t
    ON c.id = t.id_contract
), contract_aud_join_rev AS (
  SELECT
    ure.ts_revision,
    c_aud.id_contract,
    c_aud.tenant_service_fee AS tenant_service_fee,
    c_aud.rev
  FROM datalake_ebdb_clean.contract_aud AS c_aud
  JOIN datalake_ebdb_user.user_revision_entity AS ure
    ON c_aud.rev = ure.id
  WHERE
    c_aud.mod_tenant_service_fee = TRUE
), tenant_service_fee_history AS (
  SELECT DISTINCT
    car.id_contract,
    FIRST_VALUE(car.tenant_service_fee) OVER (PARTITION BY car.id_contract ORDER BY car.rev rows BETWEEN UNBOUNDED preceding AND UNBOUNDED following) AS first_tenant_service_fee,
    LAST_VALUE(car.tenant_service_fee) OVER (PARTITION BY car.id_contract ORDER BY car.rev rows BETWEEN UNBOUNDED preceding AND UNBOUNDED following) AS last_tenant_service_fee,
    LAST_VALUE(car.ts_revision) OVER (PARTITION BY car.id_contract ORDER BY car.rev rows BETWEEN UNBOUNDED preceding AND UNBOUNDED following) AS dt_last_tenant_service_fee_change
  FROM contract_aud_join_rev AS car
), tenant_service_fee_opt_out_info AS (
  SELECT
    sfh.id_contract,
    sfh.dt_last_tenant_service_fee_change
  FROM tenant_service_fee_history AS sfh
  WHERE
    sfh.first_tenant_service_fee <> 0 AND sfh.last_tenant_service_fee = 0
), first_rent AS (
  SELECT DISTINCT
    ca.id_contract,
    FIRST_VALUE(rent) OVER (PARTITION BY id_contract ORDER BY rev rows BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS first_rent
  FROM datalake_ebdb_clean.contract_aud AS ca
  WHERE
    status_closing = 'ContratoAssinado'
), contract_anomaly AS (
  SELECT
    c.id AS id_contract,
    IF(
      DATE_ADD(t.dt_vacancy, 20) > t.dt_termination_finished
      OR (
        t.dt_termination_finished IS NULL AND DATE_ADD(t.dt_vacancy, 20) > CURRENT_DATE
      ),
      FALSE,
      TRUE
    ) AS is_contract_anomaly
  FROM datalake_ebdb_clean.contract AS c
  JOIN terminations AS t
    ON c.id = t.id_contract
  WHERE
    t.status <> 'CANCELED'
), last_status_condo_monitoring AS (
  SELECT
    id_contract,
    action_type
  FROM (
    SELECT
      id_contract,
      action_type,
      ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY ts_updated DESC) AS _w,
      ts_updated
    FROM datalake_rental_management_clean.condo_monitoring_actions
  ) AS _t
  WHERE
    _w = 1
), last_brokerage_share_revision AS (
  SELECT
    id_contract,
    agent_brokerage_share,
    ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY ts_revision DESC) = 1 AS is_last_revision
  FROM datalake_big_agent.brokerage_share_history
)
SELECT
  c.id,
  ch.id_country,
  c.id_proposal,
  c.id_house,
  c.id_user,
  ch.country_code,
  c.rent,
  CASE
    WHEN c.rent <= 1500
    THEN 'LOW'
    WHEN c.rent < 2500
    THEN 'MEDIUM'
    WHEN c.rent >= 2500
    THEN 'HIGH'
    ELSE 'UNDEFINED'
  END AS value_segment,
  fre.first_rent AS first_rent_charged,
  c.billing_day_of_month,
  c.guarantee_type,
  c.type,
  c.status,
  COALESCE(GET_JSON_OBJECT(c.contract_rent_model, rentalAdministrator), 'QUINTOANDAR') AS rental_administrator,
  c.paying_condo,
  c.responsible_for_condo,
  c.paying_iptu,
  c.responsible_for_iptu,
  lscm.action_type AS condo_monitoring_status,
  c.rental_guarantee_installment,
  c.rental_guarantee_value,
  c.home_insurance_installment,
  c.home_insurance_value,
  c.fist_rent_comission_fee, /* TODO this column name is wrong and must be updated to first_rent_comission_fee */
  c.condo_price,
  c.iptu,
  c.tenant_service_fee,
  bsh.agent_brokerage_share,
  (
    NOT sfo.id_contract IS NULL
  ) AS is_tenant_service_fee_opt_out,
  dt_last_tenant_service_fee_change AS ts_tenant_service_fee_opt_out,
  c.is_exit_inspection_opted_out,
  c.signature_type,
  c.status_closing,
  REGEXP_EXTRACT(cv.version_display_contract, '^v[^_]+', 0) AS contract_version,
  COALESCE(oc.is_ongoing_contract, FALSE) AS is_ongoing_contract,
  cm.is_waiting_to_be_signed,
  cm.is_active_or_ended,
  cm.is_canceled,
  cm.is_ended,
  cm.is_full_service,
  cm.is_deal_only,
  COALESCE(c.is_relisting_enabled, FALSE) AS is_relisting_enabled,
  ca.is_contract_anomaly,
  NOT cme.id_contract IS NULL AS is_condo_monitoring_eligible,
  lscm.action_type = 'ACTIVATED' AS is_condo_monitoring_active,
  fc.monthly_administration_fee,
  ccr.cancellation_reason,
  ccr.ts_canceled,
  aad.ts_analyst_annulment_input,
  c.dt_started,
  c.dt_entered,
  IF(
    t.status = 'DONE' AND c.dt_termination > CAST('2020-01-07' AS DATE),
    t.dt_vacancy,
    c.dt_termination
  ) AS dt_termination, /* The date filter is when Terminator became the source for terminations */
  c.ts_signed,
  c.ts_expected_termination,
  c.ts_contract_expected_end AS dt_contract_expected_end, /* TODO [ODS] rename col to dt_contract_expected_end in clean */
  c.ts_minuta_approved,
  c.ts_created,
  c.ts_updated,
  CAST(COALESCE(
    aad.ts_analyst_annulment_input,
    IF(
      t.status = 'DONE' AND c.dt_termination > CAST('2020-01-07' AS DATE),
      t.dt_vacancy,
      c.dt_termination
    )
  ) AS DATE) AS dt_ended_rental_confirmed
FROM datalake_ebdb_clean.contract AS c
LEFT JOIN last_brokerage_share_revision AS bsh
  ON bsh.id_contract = c.id AND bsh.is_last_revision IS TRUE
LEFT JOIN contract_cancellation_reason AS ccr
  ON ccr.id_contract = c.id
LEFT JOIN contract_analyst_annulment_date AS aad
  ON aad.id_contract = c.id
LEFT JOIN ongoing_contracts AS oc
  ON oc.id_contract = c.id
LEFT JOIN contract_metrics AS cm
  ON cm.id_contract = c.id
LEFT JOIN datalake_ebdb_clean.contract_version AS cv
  ON cv.id = c.id_contract_version
LEFT JOIN datalake_ebdb_clean.full_contract AS fc
  ON fc.id = c.id
LEFT JOIN tenant_service_fee_opt_out_info AS sfo
  ON c.id = sfo.id_contract
LEFT JOIN first_rent AS fre
  ON fre.id_contract = c.id
JOIN datalake_ebdb_country.house AS ch
  ON ch.id_house = c.id_house
LEFT JOIN terminations AS t
  ON t.id_contract = c.id
LEFT JOIN contract_anomaly AS ca
  ON ca.id_contract = c.id
LEFT JOIN datalake_rental_management_clean.condo_monitoring_eligibility AS cme
  ON c.id = cme.id_contract
LEFT JOIN last_status_condo_monitoring AS lscm
  ON c.id = lscm.id_contract
