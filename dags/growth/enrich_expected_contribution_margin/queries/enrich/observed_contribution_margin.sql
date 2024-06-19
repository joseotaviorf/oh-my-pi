WITH contracts_table AS (
    SELECT
        id AS id_contract,
        date_format(dt_termination, "yyyy-MM-01") AS dt_termination
    FROM
        datalake_ebdb_clean.contract
), rent_flows_table AS (
    SELECT DISTINCT
        id_rent_flow,
        id_house,
        id_tenant_prospect,
        id_contract
    FROM
        datalake_rent_demand_events.rent_demand_events
    WHERE
        id_event = id_contract
        AND id_event_type = 9
), revenue_table AS (
    SELECT
        id_rent_flow,
        id_house,
        id_tenant_prospect,
        id_contract,
        dt_termination,
        contract_lifetime,
        dt_month_start,
        accrual_year_month,
        net_revenue_pre_taxes,
        gross_revenue
    FROM
        dw_rental_contribution_margin.fact_house_listing_revenues
    LEFT JOIN
        contracts_table USING (id_contract)
    JOIN
        rent_flows_table USING (id_contract, id_house)
    WHERE
        dt_month_start BETWEEN date_format("{start_date}", "yyyy-MM-01") AND "{end_date}"
), taxes_table as (
  SELECT
    accrual_year_month,
    tax_rate
  FROM ( 
    VALUES ('202201', -4.14),
           ('202202', -3.80),
           ('202203', -5.16),
           ('202204', -5.14),
           ('202205', -6.13),
           ('202206', -5.33),
           ('202207', -7.27),
           ('202208', -6.72),
           ('202209', -6.78),
           ('202210', -8.63),
           ('202211', -7.17),
           ('202212', -7.55),
           ('202301', -7.98),
           ('202302', -7.59),
           ('202303', -9.17),
           ('202304', -7.52),
           ('202305', -7.76),
           ('202306', -7.66),
           ('202307', -7.92),
           ('202308', -7.57),
           ('202309', -7.96),
           ('202310', -8.92),
           ('202311', -7.32),
           ('202312', -8.36),
           ('202401', -9.08),
           ('202402', -8.38),
           ('202403', -8.73),
           ('202404', -8.55)
  ) AS (accrual_year_month, tax_rate)
), contract_onboarding_costs AS (
    SELECT
        id_contract,
        contract_lifetime,
        800 AS pre_rental_costs,
        255 AS onboarding_costs
    FROM
        revenue_table
    WHERE
        contract_lifetime = 0
), contract_ongoing_costs AS (
    SELECT
        id_contract,
        contract_lifetime,
        25 AS ongoing_costs
    FROM
        revenue_table
    WHERE
        contract_lifetime > 0
        AND NOT (
            dt_termination IS NOT NULL
            AND dt_month_start = dt_termination
        )
), contract_offboarding_costs AS (
    SELECT
        id_contract,
        contract_lifetime,
        700 AS offboarding_costs
    FROM
        revenue_table
    WHERE
        dt_termination IS NOT NULL
        AND dt_month_start = dt_termination
), provision_table AS (
    SELECT
        id_contract,
        date_format(dt_closing, "yyyy-MM-01") AS dt_month_start,
        sum(provision_balance_p4_delay_e) AS provision_balance
    FROM
        datalake_losses.provision
    WHERE
        dt_closing >= date_format(add_months("{start_date}", -1), "yyyy-MM-01")
    GROUP BY ALL
), losses_table AS (
    SELECT
        id_contract,
        dt_month_start,
        provision_balance - lag(provision_balance) OVER (
            PARTITION BY id_contract
            ORDER BY dt_month_start
        ) AS losses
    FROM
        provision_table
    WHERE
        dt_month_start <> date_format(add_months(current_date, -1), "yyyy-MM-01")
), final_table AS (
    SELECT
        * EXCEPT (tax_rate, losses),
        coalesce(tax_rate, -8.0) AS tax_rate,
        coalesce(losses, 0.) AS losses
    FROM
        revenue_table
    LEFT JOIN
        taxes_table USING (accrual_year_month)
    LEFT JOIN
        contract_onboarding_costs USING (id_contract, contract_lifetime)
    LEFT JOIN
        contract_ongoing_costs USING (id_contract, contract_lifetime)
    LEFT JOIN
        contract_offboarding_costs USING (id_contract, contract_lifetime)
    LEFT JOIN
        losses_table USING (id_contract, dt_month_start)
    WHERE
        (dt_termination IS NULL) OR (dt_month_start <= dt_termination)
)

SELECT
    id_rent_flow,
    id_house,
    id_tenant_prospect,
    id_contract,
    add_months(dt_month_start, -contract_lifetime) AS contract_start_month,
    CAST(dt_termination AS DATE) AS contract_termination_month,
    dt_month_start AS month_of_year,
    contract_lifetime AS months_since_contract_start,
    gross_revenue,
    net_revenue_pre_taxes * (1 + tax_rate/100) AS net_revenue,
    (
        net_revenue_pre_taxes * (1 + tax_rate/100)
        + losses
    ) AS net_revenue_after_losses,
    (
        net_revenue_pre_taxes * (1 + tax_rate/100)
        + losses
        - coalesce(pre_rental_costs, 0.)
        - coalesce(onboarding_costs, 0.)
        - coalesce(ongoing_costs, 0.)
        - coalesce(offboarding_costs, 0.)
    ) AS contribution_margin
FROM
    final_table
