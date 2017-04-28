DROP VIEW vw_rental_mgmt_ongoing_and_offboarding_costs CASCADE;
CREATE VIEW vw_rental_mgmt_ongoing_and_offboarding_costs AS
  WITH c_dates AS (
      SELECT
        contract.id                                             AS contract_id,
        contract.imovel_id,
        contract."criadoEm"                                     AS created_date,
        contract."dataAssinado"                                 AS signature_date,
        coalesce(contract."dataEntrada", contract."dataInicio") AS contract_init_date,
        contract.status,
        CASE
        WHEN ((contract.status) :: TEXT = ANY
              (ARRAY [('Ativo' :: CHARACTER VARYING) :: TEXT, ('PreAssinaturas' :: CHARACTER VARYING) :: TEXT]))
          THEN COALESCE((contract."dataRescisao") :: TIMESTAMP WITHOUT TIME ZONE,
                        (contract."dataFimContratoPrevisto") :: TIMESTAMP WITHOUT TIME ZONE, contract."atualizadoEm")
        WHEN ((contract.status) :: TEXT = ANY
              (ARRAY [('Cancelado' :: CHARACTER VARYING) :: TEXT, ('Finalizado' :: CHARACTER VARYING) :: TEXT]))
          THEN COALESCE((contract."dataRescisao") :: TIMESTAMP WITHOUT TIME ZONE, contract."atualizadoEm")
        ELSE contract."atualizadoEm"
        END                                                     AS contract_date
      FROM contract
  ), all_dates AS (
      SELECT DISTINCT
        cd.contract_id,
        cd.imovel_id,
        cd.created_date,
        cd.signature_date,
        cd.contract_date,
        date_trunc('month' :: TEXT, (dd.date) :: TIMESTAMP WITHOUT TIME ZONE) AS date_range
      FROM (dim_date dd
        JOIN c_dates cd
          ON ((
          (dd.date >= (date_trunc('month' :: TEXT, (cd.contract_init_date) :: TIMESTAMP WITHOUT TIME ZONE)) :: DATE) AND
          (dd.date <=
           CASE
           WHEN (((cd.status) :: TEXT = ANY
                  (ARRAY [('Cancelado' :: CHARACTER VARYING) :: TEXT, ('Finalizado' :: CHARACTER VARYING) :: TEXT]))
                 OR (cd.contract_init_date IS NULL))
             THEN ((date_trunc('month' :: TEXT, cd.contract_date)) :: DATE) :: TIMESTAMP WITHOUT TIME ZONE
           ELSE ((date_trunc('month' :: TEXT, (cd.contract_init_date) :: TIMESTAMP WITHOUT TIME ZONE)) :: DATE +
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
  ), cdre_ocormoff AS (
      SELECT
        costs_dre."Value"    AS value,
        costs_dre."Month"    AS dre_date,
        costs_dre."Category" AS category
      FROM files.costs_dre
      WHERE ((costs_dre."Category") :: TEXT = ANY
             (ARRAY [('Ongoing & Conflicts' :: CHARACTER VARYING) :: TEXT, ('Other Rental Management Costs' :: CHARACTER VARYING) :: TEXT, ('Offboarding' :: CHARACTER VARYING) :: TEXT]))
  ), cdre_dates AS (
      SELECT
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
        co.value,
        co.category,
        CASE
        WHEN (date_part('month' :: TEXT, (co.dre_date) :: TIMESTAMP WITHOUT TIME ZONE) =
              date_part('month' :: TEXT, ct.created_date))
          THEN ct.init_days
        WHEN (date_part('month' :: TEXT, (co.dre_date) :: TIMESTAMP WITHOUT TIME ZONE) =
              date_part('month' :: TEXT, ct.contract_date))
          THEN ct.end_days
        ELSE date_part('days' :: TEXT,
                       ((date_trunc('month' :: TEXT, (co.dre_date) :: TIMESTAMP WITHOUT TIME ZONE) +
                         '1 mon' :: INTERVAL)
                        - (co.dre_date) :: TIMESTAMP WITHOUT TIME ZONE))
        END AS cost_days
      FROM (ct
        LEFT JOIN cdre_ocormoff co ON (((co.dre_date) :: TIMESTAMP WITHOUT TIME ZONE = ct.date_range)))
  ), termination_date_count AS (
      SELECT
        DISTINCT
        date_range,
        count(contract_id) AS contract_count
      FROM cdre_dates
      WHERE date_range = date_trunc('month', termination_date) :: DATE
      GROUP BY cdre_dates.date_range, cdre_dates.category
  )
    , pre_final_result AS (
      SELECT
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
        (SELECT contract_count
         FROM termination_date_count
         WHERE date_range = cdre_dates.date_range)                                      AS termination_count,
        count(*)
        OVER w                                                                          AS costs_count_per_contract,
        count(*)
        OVER w_offboarding                                                              AS costs_count_per_contract_terminated,
        (SELECT contract_count
         FROM termination_date_count
         WHERE date_range = cdre_dates.date_range)                                      AS termination_sum,
        (count(*)
        OVER w) + (count(*)
        OVER w_offboarding)                                                             AS sum_costs,
        date_part('days' :: TEXT, ((date_trunc('month' :: TEXT, cdre_dates.date_range) + '1 mon' :: INTERVAL) -
                                   cdre_dates.date_range))                              AS current_month_days,
        sum(cdre_dates.cost_days)
        OVER w                                                                          AS current_month_sum,
        (cdre_dates.value / ((COALESCE(NULLIF(
                                           (count(*)
                                           OVER w) +
                                           (SELECT contract_count
                                            FROM termination_date_count
                                            WHERE date_range = cdre_dates.date_range)
                                           , 0),
                                       (1) :: BIGINT)) :: NUMERIC) :: DOUBLE PRECISION) AS average_ongoing_cost,
        CASE
        WHEN ((cdre_dates.termination_date IS NULL) OR (date_trunc('month' :: TEXT, cdre_dates.date_range) <>
                                                        date_trunc('month' :: TEXT,
                                                                   (cdre_dates.termination_date) :: TIMESTAMP WITHOUT TIME ZONE)))
          THEN (0) :: DOUBLE PRECISION
        --                     ELSE (cdre_dates.value / ((COALESCE(NULLIF(count((date_trunc('month'::text, (cdre_dates.termination_date)::timestamp without time zone) = date_trunc('month'::text, cdre_dates.date_range))) OVER w, 0), (1)::bigint))::numeric)::double precision)
        ELSE (cdre_dates.value /
              ((COALESCE(NULLIF(
                             (count(*)
                             OVER w) +
                             (SELECT contract_count
                              FROM termination_date_count
                              WHERE date_range = cdre_dates.date_range)
                             , 0), (1) :: BIGINT)) :: NUMERIC) :: DOUBLE PRECISION)
        END                                                                             AS average_offboarding_cost,
        ((cdre_dates.value * cdre_dates.cost_days) / sum(cdre_dates.cost_days)
        OVER w)                                                                         AS average_days_cost
      FROM cdre_dates
      WINDOW w AS (
        PARTITION BY cdre_dates.date_range, cdre_dates.category )
        , w_offboarding AS (
        PARTITION BY cdre_dates.date_range, cdre_dates.category, (date_trunc('month' :: TEXT,
                                                                             (cdre_dates.termination_date) :: TIMESTAMP WITHOUT TIME ZONE)) )
      ORDER BY cdre_dates.date_range
  ), final_result AS (
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
        pre_final_result.costs_count_per_contract,
        pre_final_result.costs_count_per_contract_terminated,
        pre_final_result.sum_costs,
        pre_final_result.average_offboarding_cost,
        pre_final_result.average_ongoing_cost,
        sum(pre_final_result.average_ongoing_cost)
        OVER (
          PARTITION BY pre_final_result.contract_id, pre_final_result.imovel_id, pre_final_result.date_range ) AS total_ongoing_avg,
        sum(pre_final_result.average_offboarding_cost)
        OVER (
          PARTITION BY pre_final_result.contract_id, pre_final_result.imovel_id, pre_final_result.date_range ) AS total_offboarding_avg
      FROM pre_final_result
  )
  SELECT
    final_result.contract_id,
    final_result.imovel_id,
    final_result.rent_value,
    final_result.created_date,
    final_result.updated_date,
    final_result.signature_date,
    final_result.termination_date,
    final_result.contract_end_date,
    final_result.contract_date,
    final_result.init_days,
    final_result.end_days,
    final_result.full_contract_days,
    final_result.total_month_year_cost,
    final_result.date_range,
    final_result.cost_days,
    final_result.current_month_days,
    final_result.current_month_sum,
    final_result.costs_count_per_contract,
    final_result.costs_count_per_contract_terminated,
    final_result.sum_costs,
    COALESCE(final_result.average_offboarding_cost, (0) :: DOUBLE PRECISION)                          AS average_offboarding_cost,
    final_result.average_ongoing_cost,
    final_result.total_offboarding_avg,
    final_result.total_ongoing_avg,
    gap_fill(final_result.total_ongoing_avg)
    OVER (
      PARTITION BY final_result.contract_id, final_result.imovel_id
      ORDER BY final_result.date_range )                                                              AS gap_fill,
    ((final_result.total_ongoing_avg IS NOT NULL) OR (final_result.total_ongoing_avg IS NOT NULL))    AS flg_incurred,
    ((gap_fill(final_result.total_ongoing_avg)
      OVER (
        PARTITION BY final_result.contract_id, final_result.imovel_id
        ORDER BY final_result.date_range ) IS NOT NULL) AND (final_result.total_ongoing_avg IS NULL)) AS flg_projected
  FROM final_result