WITH business_keys as (
  SELECT DISTINCT
    CONCAT_WS("#",
    COALESCE(LOWER(is_3p_demand),0),
    COALESCE(LOWER(user_sale_booking_creator),0)
    ) AS bk_operation_flow,
    is_3p_demand,
    user_sale_booking_creator
  FROM
    datalake_booking.booking
),

business_rules AS (
  SELECT
    bk_operation_flow,
    CASE
      WHEN user_sale_booking_creator IS NULL THEN "Lost Tracking"
      WHEN user_sale_booking_creator = 'Admin/CX' THEN 'CX'
      WHEN user_sale_booking_creator = 'Prospect' THEN 'SelfService'
      ELSE user_sale_booking_creator 
    END AS operation_channel,
    CASE
      WHEN is_3p_demand = TRUE THEN 'Rede'
      WHEN user_sale_booking_creator = 'Agent' AND is_3p_demand = FALSE THEN 'Agent'
      ELSE 'NA'
    END AS referral_type,
    NOW() AS ts_load
  FROM
    business_keys AS bks
),

last_id_values AS (
    SELECT
        COALESCE(MAX(id_demand_operation_flow), 0) AS max_id_demand_operation_flow
    FROM
      datalake_growth_taxonomy.demand_operation_flow
)

SELECT
  COALESCE(
      dof.id_demand_operation_flow,
      liv.max_id_demand_operation_flow + MONOTONICALLY_INCREASING_ID() + 1
  ) AS id_demand_operation_flow,
  br.bk_operation_flow,
  br.operation_channel,
  br.referral_type,
  COALESCE(dof.ts_combination_created, NOW()) AS ts_combination_created,
  NOW() AS ts_load
FROM
  business_rules AS br
CROSS JOIN
  last_id_values AS liv
LEFT JOIN
  datalake_growth_taxonomy.demand_operation_flow AS dof
    ON br.operation_channel = dof.operation_channel
    AND br.referral_type = dof.referral_type