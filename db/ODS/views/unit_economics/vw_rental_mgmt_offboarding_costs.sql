DROP VIEW vw_rental_mgmt_offboarding_costs CASCADE;
CREATE VIEW vw_rental_mgmt_offboarding_costs AS
  WITH all_dates AS (
      SELECT DISTINCT
        cd.contract_id,
        cd.imovel_id,
        cd.created_date,
        cd.signature_date,
        cd.contract_date,
        date_trunc('month' :: TEXT, (dd.date) :: TIMESTAMP WITH TIME ZONE) AS date_range
      FROM (dim_date dd
        JOIN vw_rental_mgmt_contract cd ON (((dd.date >= cd.contract_init_date) AND (dd.date <=
                                                                                     CASE
                                                                                     WHEN (((cd.status) :: TEXT = ANY
                                                                                            (ARRAY [('Cancelado' :: CHARACTER VARYING) :: TEXT, ('Finalizado' :: CHARACTER VARYING) :: TEXT]))
                                                                                           OR (cd.contract_init_date IS
                                                                                               NULL))
                                                                                       THEN cd.contract_date
                                                                                     ELSE (cd.contract_init_date +
                                                                                           ((30) :: DOUBLE PRECISION *
                                                                                            '1 mon' :: INTERVAL))
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
  ), cdre_ocro AS (
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
        co.dre_date,
        CASE
        WHEN (((co.category) :: TEXT = 'Offboarding' :: TEXT) AND (date_part('month' :: TEXT, ct.termination_date) =
                                                                   date_part('month' :: TEXT,
                                                                             (co.dre_date) :: TIMESTAMP WITHOUT TIME ZONE)))
          THEN co.value
        ELSE (0) :: DOUBLE PRECISION
        END AS offboarding_double_accounting,
        CASE
        WHEN ((date_part('month' :: TEXT, (co.dre_date) :: TIMESTAMP WITHOUT TIME ZONE) >=
               date_part('month' :: TEXT, ct.created_date)) AND
              (date_part('year' :: TEXT, (co.dre_date) :: TIMESTAMP WITHOUT TIME ZONE) >=
               date_part('year' :: TEXT, ct.created_date)))
          THEN ct.init_days
        ELSE NULL :: DOUBLE PRECISION
        END AS cost_days
      FROM (ct
        LEFT JOIN cdre_ocro co ON (((co.dre_date) :: TIMESTAMP WITHOUT TIME ZONE = ct.date_range)))
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
        cdre_dates.offboarding_double_accounting,
        cdre_dates.dre_date,
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
        OVER w)                                                                         AS average_days_cost,
        (((cdre_dates.value * cdre_dates.end_days) / sum(cdre_dates.end_days)
        OVER w) + ((cdre_dates.offboarding_double_accounting * cdre_dates.cost_days) / sum(cdre_dates.cost_days)
        OVER w))                                                                        AS total_average_days_cost,
        ((cdre_dates.offboarding_double_accounting * cdre_dates.end_days) / sum(cdre_dates.end_days)
        OVER w)                                                                         AS average_days_cost_db_acc
      FROM cdre_dates
      WINDOW w AS (
        PARTITION BY (date_part('month' :: TEXT, cdre_dates.date_range)), (date_part('year' :: TEXT,
                                                                                     cdre_dates.date_range)) )
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
        pre_final_result.contracts_count,
        pre_final_result.average_contract_cost,
        sum(pre_final_result.average_contract_cost)
        OVER (
          PARTITION BY pre_final_result.contract_id, pre_final_result.imovel_id, pre_final_result.date_range ) AS total_avg
      FROM pre_final_result
  ), update_final_result AS (
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
        final_result.contracts_count,
        final_result.average_contract_cost,
        final_result.total_avg,
        gap_fill(final_result.total_avg)
        OVER (
          PARTITION BY final_result.contract_id, final_result.imovel_id
          ORDER BY final_result.date_range )                                                      AS cost,
        (final_result.total_avg IS NOT NULL)                                                      AS flg_incurred,
        ((gap_fill(final_result.total_avg)
          OVER (
            PARTITION BY final_result.contract_id, final_result.imovel_id
            ORDER BY final_result.date_range ) IS NOT NULL) AND (final_result.total_avg IS NULL)) AS flg_projected
      FROM final_result
  )
  SELECT
    update_final_result.contract_id,
    update_final_result.imovel_id,
    dense_rank()
    OVER (
      PARTITION BY update_final_result.contract_id, update_final_result.imovel_id
      ORDER BY update_final_result.date_range ) AS rn,
    update_final_result.rent_value,
    update_final_result.created_date,
    update_final_result.updated_date,
    update_final_result.signature_date,
    update_final_result.termination_date,
    update_final_result.contract_end_date,
    update_final_result.contract_date,
    update_final_result.init_days,
    update_final_result.end_days,
    update_final_result.full_contract_days,
    update_final_result.total_month_year_cost,
    update_final_result.date_range,
    update_final_result.cost_days,
    update_final_result.current_month_days,
    update_final_result.current_month_sum,
    update_final_result.contracts_count,
    update_final_result.average_contract_cost,
    update_final_result.total_avg,
    CASE
    WHEN ((update_final_result.cost IS NOT NULL) AND (update_final_result.flg_projected IS TRUE) AND
          (update_final_result.total_month_year_cost IS NULL))
      THEN NULL :: DOUBLE PRECISION
    ELSE update_final_result.cost
    END                                         AS cost,
    update_final_result.flg_incurred,
    update_final_result.flg_projected
  FROM update_final_result;

