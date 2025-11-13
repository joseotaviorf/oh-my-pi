WITH termination_base as (
  SELECT 
    DISTINCT MAX(t.id) id_request, 
    t.id_contract, 
    MAX(
      DATE(t.dt_vacancy)
    ) termination_date, 
    t.status
  FROM 
    datalake_terminator_clean.termination t 
    LEFT JOIN datalake_offboarding.contract_termination dt ON t.id = dt.id_termination 
    LEFT JOIN dw_rent.dim_contract dc ON t.id_contract = dc.sk_contract 
    LEFT JOIN (
      SELECT 
        fi.sk_contract, 
        fi.ts_synced, 
        fi.sk_inspection, 
        di.inspection_type, 
        ROW_NUMBER() OVER (
          PARTITION BY fi.sk_contract, fi.ts_synced ORDER BY fi.ts_synced
        ) rn 
      FROM 
        dw_inspections.fact_inspection fi 
        LEFT JOIN dw_inspections.dim_inspection di ON fi.sk_inspection = di.sk_inspection 
      WHERE 
        di.inspection_type IN ('offboarding', 'verification')
    ) ins ON t.id_contract = ins.sk_contract 
    AND ins.rn = 1 
  WHERE 
    dc.country_code = 'BR' 
    AND t.ts_created BETWEEN DATE('{load_start_date}') - INTERVAL '12' MONTH 
    AND DATE('{load_end_date}' - INTERVAL '1' day)
    AND t.ts_created >= DATE('2025-01-01')
  GROUP BY 
    2, 
    4
), 
base AS (
  SELECT 
    DISTINCT date(
      fi.ts_inspected - INTERVAL '3' HOUR
    ) AS fi_dt_inspected, 
    fi.sk_inspection AS fi_sk_inspection, 
    fi.sk_main_inspection AS fi_sk_main_inspection, 
    fi.sk_booking AS fi_sk_booking, 
    fi.sk_contract AS fi_sk_contract, 
    fi.dt_contract_entrance AS fi_dt_contract_entrance, 
    tc.termination_date AS fi_dt_contract_termination, 
    tc.status as status_contract,
    fi.dt_execution_limit AS fi_dt_execution_limit, 
    fi.ts_booking_cancelled AS fi_ts_booking_cancelled, 
    fi.ts_termination_canceled AS fi_ts_termination_canceled, 
    fi.ts_created AS fi_ts_created, 
    DATE(fi.ts_booking_inspected_local) AS fi_ts_booking_inspected_local, 
    fi.ts_booking_cancelled_local AS fi_ts_booking_cancelled_local, 
    fi.booking_type AS fi_booking_type, 
    fi.is_d0_canceled AS fi_is_d0_canceled, 
    fi.is_d1_canceled AS fi_is_d1_canceled, 
    fi.ts_inspected AS fi_ts_inspected, 
    fi.sk_inspector AS fi_sk_inspector, 
    date(fi.ts_synced - INTERVAL '3' HOUR) AS fi_ts_synced, 
    fi.ts_booking_created_local AS fi_ts_booking_created_local, 
    fi.sk_house AS fi_sk_house, 
    di.inspection_type AS di_inspection_type, 
    di.source AS di_source, 
    di.status AS di_status,
    di.ts_created AS di_ts_created, 
    dr.city_name AS dr_city_name,
    ww.dt_end_3 as ww_dt_end_3,
    DATE_ADD(DAY, 4, DATE(tc.termination_date)) AS dt_end_3,
    db.cancellation_reason,
    IF(db.cancellation_reason IN ('CANCELED_INSPECTOR_NOT_ATTEND', 'INSPECTOR_BLOCKED_SCHEDULE', 'CANCELED_INSPECTOR_CAN_NOT_ATTEND_INSPECTION', 'CANCELED_OTHER_INSPECTOR') 
      AND DATE_DIFF(DAY, DATE(fi.ts_booking_inspected_local), DATE(fi.ts_booking_cancelled_local))  >= -1 ,1,0) as canc_critico,
    CASE
    WHEN DATE_DIFF(DAY, date(fi.ts_booking_cancelled_local), DATE(fi.ts_booking_inspected_local)) = 0 THEN 1
    ELSE 0 
      END AS canc_D0,
    CASE 
    WHEN DATE_DIFF(DAY, date(fi.ts_booking_cancelled_local), DATE(fi.ts_booking_inspected_local)) = 1 THEN 1
    ELSE 0 
      END AS canc_D1,
    CASE 
      WHEN db.cancellation_reason IN ('REPURPOSE_BECAUSE_OF_BUG', 'CANCELED_INTERNAL_BUG', 'BUG_IN_INSPECTION_APP') THEN 'BUG'
      WHEN db.cancellation_reason IN ('RESCHEDULING_CONTRACT', 'EXPECTED_TERMINATION_DATE_CHANGE', 'CANCELED_CONTRACT_CANCELED', 'CANCELED_OWNER_EXEMPTED_INSPECTION', 'CANCELED_OWNER_NOT_RENTING', 'CANCELED_OWNER_WAITING_CONTRACT', 'CANCELED_EXIT_INSPECTION_OPT_OUT', 'CANCELED_AUTOMATICALLY_PROPERTY_UNPUBLISHED', 'CANCELED_PROPERTY_SUSPENDED_ADVANCED_NEGOTIATIONS') THEN 'CONTRACT'
      WHEN db.cancellation_reason IN ('RESCHEDULING_HOUSEFUL', 'CANCELED_INTERNAL_INSPECTOR_INACTIVE', 'CANCELED_INSPECTION_ANTICIPATION', 'CANCELED_INTERNAL_RESCHEDULED', 'RESCHEDULING_BY_HIGHER_PRIORITY_INSPECTION', 'RECYCLE_OLDER_INSPECTION', 'BAD_SCHEDULING', 'CANCELED_AUTOMATICALLY_DUE_TO_RESCHEDULING', 'ROUTE_OPTIMIZATION', 'SCHEDULE_COMPENSATION') THEN '5A'
      WHEN db.cancellation_reason IN ('CANCELED_HOUSE_INACCESSIBLE', 'CANCELED_INSPECTOR_WITHOUT_KEYS', 'CANCELED_TENANT_INSPECTOR_WITHOUT_KEYS', 'CANCELED_TENANT_HOUSE_INACCESSIBLE', 'CANCELED_HOUSE_OCCUPIED', 'CANCELED_HOUSE_REPAIRING', 'CANCELED_CLIENT_IS_STILL_IN_PROPERTY', 'CANCELED_CLIENT_IS_REPAIRING_HOUSE', 'CANCELED_OWNER_HOUSE_WITH_TENANT', 'CANCELED_OWNER_IS_REPAIRING_HOUSE', 'KEY_HOLDER_AGENT_NOT_AVAILABLE') THEN 'ACCESS'
      WHEN db.cancellation_reason IN ('CANCELED_INSPECTOR_NOT_ATTEND', 'INSPECTOR_BLOCKED_SCHEDULE', 'CANCELED_INSPECTOR_CAN_NOT_ATTEND_INSPECTION', 'CANCELED_OTHER_INSPECTOR') THEN 'VT'
      WHEN db.cancellation_reason IN ('CANCELED_BY_OWNER_FROM_LINK', 'CANCELED_OWNER_UNREACHABLE', 'CANCELED_OWNER_CAN_NOT_ATTEND', 'CANCELED_OWNER_DID_NOT ATTEND', 'CANCELED_OWNER_CANT_CONTACT_OWNER', 'CANCELED_OTHER_OWNER', 'CANCELED_OWNER_CAN_NOT ATTEND INSPECTION', 'CANCELED_OWNER_FROM_FORMS', 'CANCELED_BY_OWNER_FROM_APP','CANCELED_OWNER_DID_NOT_ATTEND') THEN 'PP'
      WHEN db.cancellation_reason IN ('CANCELED_CLIENT_CAN_NOT_ATTEND', 'CANCELED_TENANT_CAN_NOT_ATTEND_INSPECTION', 'CANCELED_TENANT_CANT_CONTACT_TENANT', 'CANCELED_TENANT_DID_NOT_ATTEND', 'CANCELED_OTHER_CLIENT', 'CANCELED_BY_TENANT_FROM_APP') THEN 'IQ'
      WHEN db.cancellation_reason = 'OTHER' THEN 'OTHER'
      ELSE NULL END as cancellation_reason_category,
    dc.status AS dc_status
      
  FROM 
     dw_inspections.fact_inspection fi 
    LEFT JOIN dw_public.dim_booking db ON fi.sk_booking = db.sk_booking
    LEFT JOIN dw_inspections.dim_inspection di ON di.sk_inspection = fi.sk_inspection 
    LEFT JOIN dw_rent.fact_contracts fc ON fi.sk_contract = fc.sk_contract
    LEFT JOIN dw_public.dim_region AS dr ON fc.sk_region = dr.sk_region
    LEFT JOIN termination_base tc on tc.id_contract = fi.sk_contract 
    LEFT JOIN datalake_date.workday_window ww ON ww.dt_ref = DATE(tc.termination_date) AND dr.city_id = COALESCE(ww.id_city, 39) 
    LEFT JOIN dw_rent.dim_contract dc ON dc.sk_contract = fi.sk_contract
    LEFT JOIN datalake_booking.booking b ON db.sk_booking = b.id

  WHERE 
    fi.booking_type is not null 
    AND fi.country_code = 'BR' 
), 
final as (
  --metricas são 'cadastrados' no select abaixo 
  SELECT 
    DISTINCT *, 
    (
      CASE WHEN di_inspection_type = ('offboarding') THEN 1 ELSE 0 END
    ) as offboarding_insp,
    (
      CASE WHEN di_inspection_type = ('offboarding') 
      AND date(fi_dt_inspected) <= ww_dt_end_3 THEN 1 ELSE 0 END
    ) as offboarding_insp_sla,
    
    (
      CASE WHEN di_inspection_type = ('offboarding') 
      AND date(fi_dt_inspected) <= dt_end_3 THEN 1 ELSE 0 END
    ) as offboarding_insp_sla_corrido,

    (
      CASE WHEN di_inspection_type = ('offboarding') THEN 
        DATE_DIFF(DAY, fi_dt_inspected, fi_dt_contract_termination)
       ELSE 0 END
    ) as offboarding_ldt,
   date(ww_dt_end_3) as tres_dias
  FROM 
    base 
)

, ranked_cancellations AS (
    SELECT 
        cancellation_reason,
        di_inspection_type,
        fi_sk_contract,
        canc_critico,
        ROW_NUMBER() OVER (
            PARTITION BY fi_sk_contract, di_inspection_type
            ORDER BY fi_ts_booking_created_local ASC
        ) AS rn
    FROM final
    WHERE cancellation_reason IS NOT NULL
)
, vistoriadores as (
  SELECT
      sk_inspector,
      company,
      row_number() over(partition by sk_inspector order by dt_start desc) desc_rn_id
  FROM dw_inspections.dim_inspector
  WHERE sk_inspector > 0
)
, cancelamento_via_cognito as (
  SELECT 
        CAST(GET_JSON_OBJECT(custom_fields, '$["Tipo de solicitação?"]') AS VARCHAR(255)) as tipo_de_solicitacao
       ,CAST(GET_JSON_OBJECT(custom_fields, '$["ID da Vistoria"]') AS INT) as sk_main_inspection
       ,CASE WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["ID da Vistoria"]') AS INT) IS NULL THEN 1 
             ELSE ROW_NUMBER() OVER(PARTITION BY CAST(GET_JSON_OBJECT(custom_fields, '$["ID da Vistoria"]') AS INT) ORDER BY ts_created) END asc_rn
  FROM dw_customer_support.dim_ticket 
  WHERE tags LIKE '%form_cancelamento_vistoria%' 
  AND ts_created >= DATE('{load_start_date}') - INTERVAL '12' MONTH 
  AND ts_created >= DATE('2025-01-01')
),

spoc_contracts AS (

SELECT
  ft.sk_termination,
  ft.sk_contract,
  DATE(ft.ts_termination_request) ts_termination_request,
  ft.is_spoc_contract,
  ft.is_spoc_control_group,
  da.email agent_email,
  dt.team spoc_team,
  ROW_NUMBER() OVER (PARTITION BY ft.sk_contract ORDER BY ft.ts_termination_request DESC) rn

FROM dw_offboarding.fact_terminations ft
LEFT JOIN dw_customer_support.dim_analyst da
  ON ft.sk_analyst = da.sk_analyst
LEFT JOIN dw_offboarding.dim_termination dt
  ON ft.sk_termination = dt.sk_termination

),

main_query AS (

SELECT 
  f.*,Case when f.di_inspection_type = 'offboarding' then f.ww_dt_end_3 else  f.fi_dt_contract_entrance end as data_limite_vt,
  rc.cancellation_reason as last_canc_reason,
  rc.canc_critico as last_canc_critico
  ,ROW_NUMBER() OVER (PARTITION BY f.fi_sk_contract, f.di_inspection_type ORDER BY f.fi_ts_inspected ASC) AS RANK_SLA
  , vt.company
  , ROW_NUMBER() OVER (PARTITION BY f.fi_sk_contract, f.di_inspection_type ORDER BY f.fi_ts_booking_inspected_local ASC) AS row_number_by_contract_and_insptype
  , SUM(IF(cvc.tipo_de_solicitacao IS NOT NULL or f.cancellation_reason_category = 'VT',1,0)) OVER (PARTITION BY f.fi_sk_contract, f.di_inspection_type ORDER BY f.fi_ts_booking_inspected_local ASC) AS row_number_by_contract_and_cancelation_vt_origin
FROM final f
LEFT JOIN ranked_cancellations rc on f.fi_sk_contract = rc.fi_sk_contract and rc.di_inspection_type = f.di_inspection_type and rc.rn = 1 
LEFT JOIN vistoriadores vt ON f.fi_sk_inspector = vt.sk_inspector and vt.desc_rn_id = 1
LEFT JOIN cancelamento_via_cognito cvc ON f.fi_sk_main_inspection = cvc.sk_main_inspection and cvc.asc_rn = 1
),

final_ AS (SELECT
  mq.fi_dt_inspected,
  mq.fi_sk_inspection,
  mq.fi_sk_booking,
  mq.fi_sk_contract,
  CASE WHEN spc.ts_termination_request < DATE('2025-06-02') AND spc.is_spoc_contract = TRUE AND (spc.is_spoc_control_group = FALSE OR spc.is_spoc_control_group IS NULL) THEN 'before_wave_6_lab_test'
    WHEN spc.ts_termination_request < DATE('2025-06-02') AND spc.is_spoc_contract = TRUE AND spc.is_spoc_control_group = TRUE THEN 'before_wave_6_lab_control'
    WHEN spc.ts_termination_request >= DATE('2025-05-22') AND spc.is_spoc_contract = TRUE AND (spc.is_spoc_control_group = FALSE OR spc.is_spoc_control_group IS NULL) AND (spc.spoc_team = 'ROLLOUT' OR spc.spoc_team IS NULL) THEN 'rollout'
    WHEN spc.ts_termination_request BETWEEN DATE('2025-06-02') AND DATE('2025-07-29') AND spc.is_spoc_contract = TRUE AND (spc.is_spoc_control_group = FALSE OR spc.is_spoc_control_group IS NULL) AND spc.spoc_team = 'LAB' THEN 'wave_6_lab_test'
    WHEN spc.ts_termination_request BETWEEN DATE('2025-07-30') AND DATE('{load_start_date}') AND spc.is_spoc_contract = TRUE AND (spc.is_spoc_control_group = FALSE OR spc.is_spoc_control_group IS NULL) AND spc.spoc_team = 'LAB' THEN 'wave_6b_lab_test'
    WHEN spc.ts_termination_request BETWEEN DATE('2025-06-02') AND DATE('2025-07-29') AND spc.is_spoc_contract = TRUE AND spc.is_spoc_control_group = TRUE THEN 'wave_6_lab_control'
    WHEN spc.ts_termination_request BETWEEN DATE('2025-07-30') AND DATE('{load_start_date}') AND spc.is_spoc_contract = TRUE AND spc.is_spoc_control_group = TRUE THEN 'wave_6b_lab_control'
  ELSE NULL
  END spoc_class,
  IF(spc.agent_email LIKE '%webhelp%', spc.agent_email, NULL) spoc_agent_email,
  mq.fi_dt_contract_termination,
  mq.status_contract,
  mq.fi_dt_execution_limit,
  mq.fi_ts_booking_cancelled,
  mq.fi_ts_termination_canceled,
  mq.fi_ts_created,
  mq.fi_ts_booking_inspected_local,
  mq.fi_ts_booking_cancelled_local,
  mq.fi_booking_type,
  mq.fi_is_d0_canceled,
  mq.fi_is_d1_canceled,
  mq.fi_ts_inspected,
  mq.fi_ts_synced,
  mq.fi_ts_booking_created_local,
  mq.fi_sk_house,
  mq.di_inspection_type,
  mq.di_source,
  mq.di_status,
  mq.di_ts_created,
  mq.dr_city_name,
  mq.ww_dt_end_3,
  mq.dt_end_3,
  mq.cancellation_reason,
  mq.canc_critico,
  mq.canc_D0,
  mq.canc_D1,
  mq.cancellation_reason_category,
  mq.dc_status,
  mq.offboarding_insp,
  mq.offboarding_insp_sla,
  mq.offboarding_insp_sla_corrido,
  mq.offboarding_ldt,
  mq.tres_dias,
  mq.data_limite_vt,
  mq.last_canc_reason,
  mq.last_canc_critico,
  mq.RANK_SLA,
  mq.company,
  mq.row_number_by_contract_and_insptype,
  mq.row_number_by_contract_and_cancelation_vt_origin,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load

FROM main_query mq
LEFT JOIN spoc_contracts spc
  ON mq.fi_sk_contract = spc.sk_contract AND spc.rn = 1

WHERE spc.is_spoc_contract = TRUE
)
SELECT*FROM final_
WHERE spoc_class NOT LIKE '%control%'
