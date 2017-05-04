DROP VIEW IF EXISTS vw_rental_mgmt_inspections_costs CASCADE;
CREATE VIEW vw_rental_mgmt_inspections_costs AS
  WITH all_dates AS (
      SELECT DISTINCT
        cd.contract_id,
        cd.imovel_id,
        cd.created_date,
        cd.signature_date,
        cd.contract_date,
        date_trunc('month', dd.date) :: TIMESTAMP WITHOUT TIME ZONE AS date_range
      FROM dim_date dd
        JOIN vw_rental_mgmt_contract cd
          ON
            dd.date BETWEEN (date_trunc('month', (cd.contract_init_date) :: TIMESTAMP WITHOUT TIME ZONE)) :: DATE AND
            CASE
            WHEN cd.status IN ('Cancelado', 'Finalizado') OR cd.contract_init_date IS NULL
              THEN ((date_trunc('month', cd.contract_date)) :: DATE) :: TIMESTAMP WITHOUT TIME ZONE
            ELSE ((date_trunc('month', (cd.contract_init_date) :: TIMESTAMP WITHOUT TIME ZONE)) :: DATE +
                  (30 * '1 mon' :: INTERVAL))
            END
  ), ct AS (
      SELECT
        co.id                                        AS contract_id,
        co.imovel_id,
        co."valorAluguel"                            AS rent_value,
        ad.date_range :: TIMESTAMP WITHOUT TIME ZONE AS date_range,
        co."criadoEm"                                AS created_date,
        co."atualizadoEm"                            AS updated_date,
        co."dataAssinado"                            AS signature_date,
        co."dataRescisao"                            AS termination_date,
        co."dataFimContratoPrevisto"                 AS contract_end_date,
        ad.contract_date,
        CASE
        WHEN date_part('days', ((date_trunc('month', co."dataAssinado") + '1 mon' :: INTERVAL) - co."dataAssinado")) > 0
          THEN date_part('days', ((date_trunc('month', co."dataAssinado") + '1 mon' :: INTERVAL) - co."dataAssinado"))
        ELSE 1
        END                                          AS init_days,
        date_part('days', ((ad.contract_date - date_trunc('month', ad.contract_date)) -
                           '1 mon' :: INTERVAL))     AS end_days,
        ((ad.contract_date) :: DATE -
         (co."dataAssinado") :: DATE)                AS full_contract_days
      FROM (contract co
        JOIN all_dates ad ON (((ad.contract_id = co.id) AND (ad.imovel_id = co.imovel_id))))
  ), cdre_inspections AS (
      SELECT
        costs_dre."Value" AS value,
        costs_dre."Month" AS dre_date
      FROM files.costs_dre
      WHERE costs_dre."Category" = 'Inspections'
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
        cc.value,
        cc.dre_date,
        date_part('days', ((date_trunc('month', ct.date_range) + '1 mon' :: INTERVAL) -
                           ct.date_range)) AS current_month_days,
        CASE
        WHEN cc.dre_date = date_trunc('month', ct.signature_date)
             OR cc.dre_date = date_trunc('month', ct.termination_date)
          THEN date_part('days', ((date_trunc('month', ct.date_range) + '1 mon' :: INTERVAL) -
                                  ct.date_range))
        ELSE NULL
        END                                AS cost_days
      FROM ct
        LEFT JOIN cdre_inspections cc ON cc.dre_date = ct.date_range
  ), pre_final_result AS (
      SELECT DISTINCT
        contract_id,
        imovel_id,
        rent_value,
        created_date,
        updated_date,
        signature_date,
        termination_date,
        contract_end_date,
        contract_date,
        init_days,
        end_days,
        full_contract_days,
        "value" AS total_month_year_cost,
        date_range,
        cost_days,
        current_month_days,
        CASE
        WHEN sum(cost_days)
             OVER w IS NULL
          THEN 0
        ELSE count(*)
        OVER w
        END     AS contracts_signed_count,
        CASE
        WHEN sum(cost_days)
             OVER w IS NULL
          THEN 0
        ELSE count(*)
        OVER w_termination
        END     AS contracts_terminated_count,
        sum(cost_days)
        OVER w  AS current_month_sum,
        count(*)
        OVER w  AS count,
        CASE
        WHEN date_range = date_trunc('month', signature_date)
          THEN ("value" / ((COALESCE(NULLIF(count(*)
                                            OVER w, 0), 1)) :: NUMERIC) :: DOUBLE PRECISION)
        WHEN date_range = date_trunc('month', termination_date)
          THEN ("value" / ((COALESCE(NULLIF(count(*)
                                            OVER w_termination, 0), 1)) :: NUMERIC) :: DOUBLE PRECISION)
        ELSE NULL
        END     AS average_contract_cost,
        ((value * cost_days) / sum(cost_days)
        OVER w) AS average_days_cost
      FROM cdre_dates
      WINDOW w AS (
        PARTITION BY date_trunc('month', date_range) ),
          w_termination AS (
          PARTITION BY date_range, date_trunc('month', cdre_dates.termination_date :: TIMESTAMP WITHOUT TIME ZONE) )
      ORDER BY date_range
  ), final_result AS (
      SELECT
        contract_id,
        imovel_id,
        rent_value,
        created_date,
        updated_date,
        signature_date,
        termination_date,
        contract_end_date,
        contract_date,
        init_days,
        end_days,
        full_contract_days,
        total_month_year_cost,
        date_range,
        cost_days,
        current_month_days,
        current_month_sum,
        contracts_signed_count,
        contracts_terminated_count,
        average_contract_cost,
        sum(average_contract_cost)
        OVER (
          PARTITION BY contract_id, imovel_id, date_range ) AS total_avg
      FROM pre_final_result
  ), updated_final_result AS (
      SELECT
        contract_id,
        imovel_id,
        rent_value,
        created_date,
        updated_date,
        signature_date,
        termination_date,
        contract_end_date,
        contract_date,
        init_days,
        end_days,
        full_contract_days,
        total_month_year_cost,
        date_range,
        cost_days,
        current_month_days,
        current_month_sum,
        contracts_signed_count,
        contracts_terminated_count,
        average_contract_cost,
        total_avg,
        gap_fill(total_avg)
        OVER w                AS cost,
        total_avg IS NOT NULL AS flg_incurred
      FROM final_result
      WINDOW w AS (
        PARTITION BY contract_id, imovel_id
        ORDER BY date_range )
  ), inspection_costs AS (
      SELECT DISTINCT
        date_range           AS max_date,
        total_avg :: NUMERIC AS cost
      FROM updated_final_result
      WHERE total_avg IS NOT NULL AND total_avg <> 0
      ORDER BY date_range DESC
      LIMIT 1
  ), projected_values AS (
      SELECT
        contract_id,
        imovel_id,
        rent_value,
        created_date,
        updated_date,
        signature_date,
        termination_date,
        contract_end_date,
        contract_date,
        init_days,
        end_days,
        full_contract_days,
        total_month_year_cost,
        date_range,
        cost_days,
        current_month_days,
        current_month_sum,
        contracts_signed_count,
        contracts_terminated_count,
        average_contract_cost,
        CASE
        WHEN cost IS NULL AND date_range > (SELECT max_date
                                            FROM inspection_costs)
          THEN (SELECT cost
                FROM inspection_costs)
        ELSE cost
        END AS cost,
        flg_incurred
      FROM updated_final_result
  )
  SELECT
    contract_id,
    imovel_id,
    rent_value,
    created_date,
    updated_date,
    signature_date,
    termination_date,
    contract_end_date,
    contract_date,
    init_days,
    end_days,
    full_contract_days,
    total_month_year_cost,
    date_range,
    cost_days,
    current_month_days,
    current_month_sum,
    contracts_signed_count,
    contracts_terminated_count,
    average_contract_cost,
    cost,
    flg_incurred,
    average_contract_cost IS NULL AND cost IS NOT NULL AND flg_incurred IS FALSE AS flg_projected
  FROM projected_values;