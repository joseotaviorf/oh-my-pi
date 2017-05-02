DROP VIEW vw_rental_mgmt_payments_costs CASCADE;
CREATE VIEW vw_rental_mgmt_payments_costs AS WITH c_dates AS (
    SELECT
      contract.id                                             AS contract_id,
      contract.imovel_id,
      contract."criadoEm"                                     AS created_date,
      contract."dataAssinado"                                 AS signature_date,
      coalesce(contract."dataEntrada", contract."dataInicio") AS contract_init_date,
      contract.status,
      CASE
      WHEN contract.status IN ('Ativo', 'PreAssinaturas')
        THEN COALESCE((contract."dataRescisao") :: TIMESTAMP WITHOUT TIME ZONE,
                      (contract."dataFimContratoPrevisto") :: TIMESTAMP WITHOUT TIME ZONE, contract."atualizadoEm")
      WHEN contract.status = 'Finalizado'
        THEN COALESCE((contract."dataRescisao") :: TIMESTAMP WITHOUT TIME ZONE, contract."atualizadoEm")
      ELSE contract."atualizadoEm"
      END                                                     AS contract_date
    FROM contract
    WHERE contract.tipo <> 'DealOnly'
          AND contract.status <> 'Cancelado'
), all_dates AS (
    SELECT DISTINCT
      cd.contract_id,
      cd.imovel_id,
      cd.created_date,
      cd.signature_date,
      cd.contract_date,
      date_trunc('month' :: TEXT, (dd.date) :: TIMESTAMP WITH TIME ZONE) AS date_range
    FROM (dim_date dd
      JOIN c_dates cd
        ON (((dd.date >= (date_trunc('month' :: TEXT, (cd.contract_init_date) :: TIMESTAMP WITH TIME ZONE)) :: DATE) AND
             (dd.date <=
              CASE
              WHEN (((cd.status) :: TEXT = ANY
                     (ARRAY [('Cancelado' :: CHARACTER VARYING) :: TEXT, ('Finalizado' :: CHARACTER VARYING) :: TEXT]))
                    OR (cd.contract_init_date IS NULL))
                THEN ((date_trunc('month' :: TEXT, cd.contract_date)) :: DATE) :: TIMESTAMP WITHOUT TIME ZONE
              ELSE ((date_trunc('month' :: TEXT, (cd.contract_init_date) :: TIMESTAMP WITH TIME ZONE)) :: DATE +
                    ((30) :: DOUBLE PRECISION * '1 mon' :: INTERVAL))
              END))))
), ct AS (
    SELECT
      co.id                                            AS contract_id,
      co.imovel_id,
      co."valorAluguel"                                AS rent_value,
      (ad.date_range) :: TIMESTAMP WITHOUT TIME ZONE   AS date_range,
      co."criadoEm"                                    AS created_date,
      co."atualizadoEm"                                AS updated_date,
      co."dataAssinado"                                AS signature_date,
      co."dataRescisao"                                AS termination_date,
      co."dataFimContratoPrevisto"                     AS contract_end_date,
      ad.contract_date,
      date_part('days' :: TEXT, ((date_trunc('month' :: TEXT, co."criadoEm") + '1 mon' :: INTERVAL) -
                                 co."criadoEm"))       AS init_days,
      date_part('days' :: TEXT, ((ad.contract_date - date_trunc('month' :: TEXT, ad.contract_date)) -
                                 '1 mon' :: INTERVAL)) AS end_days,
      ((ad.contract_date) :: DATE -
       (co."criadoEm") :: DATE)                        AS full_contract_days
    FROM (contract co
      JOIN all_dates ad ON (((ad.contract_id = co.id) AND (ad.imovel_id = co.imovel_id))))
), cdre_payments AS (
    SELECT
      costs_dre."Value" AS value,
      costs_dre."Month" AS dre_date
    FROM files.costs_dre
    WHERE ((costs_dre."Category") :: TEXT = 'Payments' :: TEXT)
), cdre_dates AS (
    SELECT DISTINCT
      ct.contract_id,
      ct.imovel_id,
      ct.rent_value,
      ct.created_date,
      ct.updated_date,
      ct.signature_date,
      ct.termination_date,
      ct.contract_end_date,
      ct.contract_date,
      ct.init_days,
      ct.end_days,
      ct.full_contract_days,
      ct.date_range,
      cp.value,
      CASE
      WHEN (date_part('month' :: TEXT, (cp.dre_date) :: TIMESTAMP WITHOUT TIME ZONE) =
            date_part('month' :: TEXT, ct.created_date))
        THEN ct.init_days
      WHEN (date_part('month' :: TEXT, (cp.dre_date) :: TIMESTAMP WITHOUT TIME ZONE) =
            date_part('month' :: TEXT, ct.contract_date))
        THEN ct.end_days
      ELSE date_part('days' :: TEXT,
                     ((date_trunc('month' :: TEXT, (cp.dre_date) :: TIMESTAMP WITHOUT TIME ZONE) + '1 mon' :: INTERVAL)
                      - (cp.dre_date) :: TIMESTAMP WITHOUT TIME ZONE))
      END AS cost_days
    FROM (ct
      LEFT JOIN cdre_payments cp ON (((cp.dre_date) :: TIMESTAMP WITHOUT TIME ZONE = ct.date_range)))
), pre_final_result AS (
    SELECT DISTINCT
      cdre_dates.contract_id,
      cdre_dates.imovel_id,
      cdre_dates.rent_value,
      cdre_dates.created_date,
      cdre_dates.updated_date,
      cdre_dates.signature_date,
      cdre_dates.termination_date,
      cdre_dates.contract_end_date,
      cdre_dates.contract_date,
      cdre_dates.init_days,
      cdre_dates.end_days,
      cdre_dates.full_contract_days,
      cdre_dates.value                                                                AS total_month_year_cost,
      cdre_dates.date_range,
      cdre_dates.cost_days,
      count(*)
      OVER w                                                                          AS contracts_count,
      date_part('days' :: TEXT, ((date_trunc('month' :: TEXT, cdre_dates.date_range) + '1 mon' :: INTERVAL) -
                                 cdre_dates.date_range))                              AS current_month_days,
      sum(cdre_dates.cost_days)
      OVER w                                                                          AS current_month_sum,
      count(*)
      OVER w                                                                          AS count,
      (cdre_dates.value / ((COALESCE(NULLIF(count(*)
                                            OVER w, 0),
                                     (1) :: BIGINT)) :: NUMERIC) :: DOUBLE PRECISION) AS average_contract_cost,
      ((cdre_dates.value * cdre_dates.cost_days) / sum(cdre_dates.cost_days)
      OVER w)                                                                         AS average_days_cost
    FROM cdre_dates
    WINDOW w AS (
      PARTITION BY (date_part('month' :: TEXT, cdre_dates.date_range)), (date_part('year' :: TEXT,
                                                                                   cdre_dates.date_range)) )
    ORDER BY cdre_dates.date_range
)
SELECT
  pre_final_result.contract_id,
  pre_final_result.imovel_id,
  pre_final_result.rent_value,
  pre_final_result.created_date,
  pre_final_result.updated_date,
  pre_final_result.signature_date,
  pre_final_result.termination_date,
  pre_final_result.contract_end_date,
  pre_final_result.contract_date,
  pre_final_result.init_days,
  pre_final_result.end_days,
  pre_final_result.full_contract_days,
  pre_final_result.total_month_year_cost,
  pre_final_result.date_range,
  pre_final_result.cost_days,
  pre_final_result.current_month_days,
  pre_final_result.current_month_sum,
  pre_final_result.contracts_count,
  pre_final_result.average_contract_cost,
  pre_final_result.average_days_cost,
  gap_fill(pre_final_result.average_days_cost)
  OVER (
    PARTITION BY pre_final_result.contract_id, pre_final_result.imovel_id
    ORDER BY pre_final_result.date_range )                            AS gap_fill,
  (pre_final_result.average_days_cost IS NOT
   NULL)                                                              AS flg_incurred,
  ((gap_fill(pre_final_result.average_days_cost)
    OVER (
      PARTITION BY pre_final_result.contract_id, pre_final_result.imovel_id
      ORDER BY pre_final_result.date_range ) IS NOT NULL) AND (pre_final_result.average_days_cost IS
                                                               NULL)) AS flg_projected
FROM pre_final_result;

