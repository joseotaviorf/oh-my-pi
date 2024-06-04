WITH base AS (
  SELECT
    inspector_control.id_inspector AS inspector_control_sk_inspector,
    inspector_info.nome AS inspector_info_name,
    inspector_info.email AS inspector_info_email,
    inspector_control.company AS inspector_control_company,
    region_info.regional_inspection AS region_info_regional_inspection,
    region_info.city_name AS region_info_city_name,
    DATE_FORMAT(DATE(
      TO_TIMESTAMP(NULLIF(CAST(inspector_control.dt_start AS STRING), ''), 'MM/dd/yyyy')
    ), 'yyyy-MM-dd') AS inspector_control_inspector_registered_start_date,
    DATE_FORMAT(DATE(TO_TIMESTAMP(NULLIF(CAST(inspector_control.dt_end AS STRING), ''), 'MM/dd/yyyy')), 'yyyy-MM-dd') AS inspector_control_inspector_registered_end_date,
    DATE_FORMAT(DATE_TRUNC('WEEK', booking_info.ts_scheduling_local), 'yyyy-MM-dd') AS booking_info_scheduling_week,
    AVG(
      CASE
        WHEN (
          csat_info.inspection_type = 'Entrada'
        )
        THEN csat_info.general_satisfaction_evaluation
        ELSE NULL
      END
    ) AS csat_info_avg_entrance_csat,
    AVG(
      CASE
        WHEN (
          csat_info.inspection_type = 'Saida'
        )
        THEN csat_info.general_satisfaction_evaluation
        ELSE NULL
      END
    ) AS csat_info_avg_exit_csat,
    COUNT(
      DISTINCT CASE
        WHEN (
          inspections.type = 'Entrada'
        )
        THEN inspections.sk_inspection
        ELSE NULL
      END
    ) AS inspections_entrance_inspections_booked,
    COUNT(
      DISTINCT CASE
        WHEN (
          inspections.type = 'Saida'
        )
        THEN inspections.sk_inspection
        ELSE NULL
      END
    ) AS inspections_exit_inspections_booked,
    COUNT(
      DISTINCT CASE
        WHEN (
          inspections.status = 'Cancelada'
        ) AND (
          inspections.type = 'Entrada'
        )
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS inspections_cancelada_entrada,
    COUNT(
      DISTINCT CASE
        WHEN (
          inspections.status = 'Cancelada'
        ) AND (
          inspections.type = 'Saida'
        )
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS inspections_cancelada_saida,
    COUNT(
      DISTINCT CASE
        WHEN (
          (
            inspections.status IN ('Revisada', 'EmRevisao', 'Finalizada', 'Comentada')
          )
        )
        AND (
          inspections.type = 'Entrada'
        )
        THEN inspections.sk_inspection
        ELSE NULL
      END
    ) AS inspections_entrance_inspections_done,
    COUNT(
      DISTINCT CASE
        WHEN (
          (
            inspections.status IN ('Revisada', 'EmRevisao', 'Finalizada', 'Comentada')
          )
        )
        AND (
          inspections.type = 'Saida'
        )
        THEN inspections.sk_inspection
        ELSE NULL
      END
    ) AS inspections_exit_inspections_done,
    COUNT(
      DISTINCT CASE
        WHEN booking_info.cancellation_reason IN ('INSPECTOR_BLOCKED_SCHEDULE', 'CANCELED_INSPECTOR_NOT_ATTEND', 'CANCELED_INSPECTOR_CAN_NOT_ATTEND_INSPECTION')
        AND (
          inspections.type = 'Entrada'
        )
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS `cancel_vt_entrada`,
    COUNT(
      DISTINCT CASE
        WHEN booking_info.cancellation_reason IN ('INSPECTOR_BLOCKED_SCHEDULE', 'CANCELED_INSPECTOR_NOT_ATTEND', 'CANCELED_INSPECTOR_CAN_NOT_ATTEND_INSPECTION')
        AND (
          inspections.type = 'Saida'
        )
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS cancel_vt_saida,
    COUNT(
      DISTINCT CASE
        WHEN (
          inspections.type = 'Entrada'
        )
        AND (
          (
            DATE(booking_info.ts_scheduling_local)
          ) = (
            DATE(inspections_window_function.cancellation_date)
          )
        )
        AND NOT booking_info.cancellation_reason IN ('CANCELED_INSPECTOR_NOT_ATTEND')
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS cancel_em_d0_entrada,
    COUNT(
      DISTINCT CASE
        WHEN (
          inspections.type = 'Saida'
        )
        AND (
          (
            DATE(booking_info.ts_scheduling_local)
          ) = (
            DATE(inspections_window_function.cancellation_date)
          )
        )
        AND NOT booking_info.cancellation_reason IN ('CANCELED_INSPECTOR_NOT_ATTEND')
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS cancel_em_d0_saida,
    COUNT(
      DISTINCT CASE
        WHEN booking_info.cancellation_reason = 'INSPECTOR_BLOCKED_SCHEDULE'
        AND (
          inspections.type = 'Entrada'
        )
        AND (
          DATEDIFF(
            DAY,
            (
              DATE(inspections_window_function.scheduling_date)
            ),
            (
              DATE(inspections_window_function.cancellation_date)
            )
          ) IN (1, 0, -1)
        )
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS fechamento_agenda_vt_em_d0_e_d_1_entrada,
    COUNT(
      DISTINCT CASE
        WHEN booking_info.cancellation_reason = 'INSPECTOR_BLOCKED_SCHEDULE'
        AND (
          inspections.type = 'Saida'
        )
        AND (
          DATEDIFF(
            DAY,
            (
              DATE(inspections_window_function.scheduling_date)
            ),
            (
              DATE(inspections_window_function.cancellation_date)
            )
          ) IN (1, 0, -1)
        )
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS fechamento_agenda_vt_em_d0_e_d_1_saida,
    COUNT(
      DISTINCT CASE
        WHEN (
          inspections.type = 'Entrada'
        )
        AND booking_info.cancellation_reason IN ('CANCELED_INSPECTOR_NOT_ATTEND')
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS no_show_entrada,
    COUNT(
      DISTINCT CASE
        WHEN (
          inspections.type = 'Saida'
        )
        AND booking_info.cancellation_reason IN ('CANCELED_INSPECTOR_NOT_ATTEND')
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS no_show_saida,
    COUNT(
      DISTINCT CASE
        WHEN (
          DATEDIFF(
            HOUR,
            inspections_window_function.scheduling_local,
            inspections_window_function.first_synced_date
          ) <= 24
        )
        AND (
          (
            inspections.status IN ('Comentada', 'EmRevisao', 'Finalizada', 'Revisada')
          )
        )
        AND (
          inspections.type = 'Entrada'
        )
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS sync_in_24h_entranda,
    COUNT(
      DISTINCT CASE
        WHEN (
          DATEDIFF(
            HOUR,
            inspections_window_function.scheduling_local,
            inspections_window_function.first_synced_date
          ) <= 24
        )
        AND (
          (
            inspections.status IN ('Comentada', 'EmRevisao', 'Finalizada', 'Revisada')
          )
        )
        AND (
          inspections.type = 'Saida'
        )
        THEN inspections.id_inspection
        ELSE NULL
      END
    ) AS sync_in_24h_saida,
    COUNT(
      DISTINCT CONCAT(
        CAST(csat_info.id_contract AS STRING),
        CAST(csat_info.inspection_type AS STRING),
        CAST(csat_info.role AS STRING)
      )
    ) AS csat_info_count_csat,
    COUNT(
      DISTINCT CASE
        WHEN (
          (
            CASE
              WHEN csat_info.general_satisfaction_evaluation > 3
              THEN 'Satisfeitos'
              WHEN csat_info.general_satisfaction_evaluation = 3
              THEN 'Neutros'
              WHEN csat_info.general_satisfaction_evaluation < 3
              THEN 'Insatisfeitos'
            END
          ) = 'Insatisfeitos'
          AND (
            improvement_tags LIKE '%Detalhes das fotos dos itens do imóvel%'
            OR improvement_tags LIKE '%Comentários do vistoriador sobre os itens do imóvel%'
          )
        )
        THEN CONCAT(
          CAST(csat_info.id_contract AS STRING),
          CAST(csat_info.inspection_type AS STRING),
          CAST(csat_info.role AS STRING)
        )
        ELSE NULL
      END
    ) AS count_dsat_tags
  FROM dw_public.dim_inspection AS inspections
  LEFT JOIN dw_public.fact_inspection_bookings AS inspection_dates
    ON inspection_dates.sk_inspection = inspections.sk_inspection
  LEFT JOIN dw_public.dim_booking AS booking_info
    ON inspection_dates.sk_booking = booking_info.sk_booking
    AND booking_info.type IN ('Vistoria', 'VistoriaQuarteirizada')
  LEFT JOIN dw_rent.dim_house_listing AS listing_info
    ON inspection_dates.sk_house_listing = listing_info.sk_house_listing
  LEFT JOIN dw_rent.fact_house_listings AS fact_house_listings
    ON listing_info.sk_house_listing = fact_house_listings.sk_house_listing
  LEFT JOIN dw_public.dim_user AS inspector_info
    ON inspector_info.sk_user = inspection_dates.sk_inspector
  LEFT JOIN datalake_gsheets_clean.inspectors_control AS inspector_control
    ON inspector_control.id_inspector = inspector_info.sk_user
  LEFT JOIN dw_public.dim_region AS region_info
    ON fact_house_listings.sk_region = region_info.sk_region
  LEFT JOIN sql_inspections_window_function AS inspections_window_function
    ON inspections.sk_inspection = inspections_window_function.sk_inspection
  LEFT JOIN sql_inspection_csat AS csat_info
    ON csat_info.id_contract = inspection_dates.sk_contract
    AND csat_info.inspection_type = inspections.type
    AND NOT inspections.status IN ('Agendada', 'Cancelada', 'ContratoCancelado')
  WHERE
    (
      (
        (
          booking_info.ts_scheduling_local
        ) >= (
          (
            DATE_ADD(DATE_TRUNC('WEEK', DATE_TRUNC('DAY', CURRENT_DATE)), -8 * 7)
          )
        )
        AND (
          booking_info.ts_scheduling_local
        ) < (
          (
            DATE_ADD(DATE_ADD(DATE_TRUNC('WEEK', DATE_TRUNC('DAY', CURRENT_DATE)), -8 * 7), 56)
          )
        )
      )
    )
    AND NOT inspector_control.id_inspector IS NULL
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9
  ORDER BY
    8 DESC
), indicadores AS (
  SELECT
    inspector_control_sk_inspector AS sk_inspector,
    inspector_info_name AS inspector_name,
    inspector_info_email AS inspector_email,
    inspector_control_company AS inspector_company,
    region_info_regional_inspection AS regional_inspection,
    region_info_city_name AS city_name,
    inspector_control_inspector_registered_start_date AS inspector_registered_start_date,
    inspector_control_inspector_registered_end_date AS inspector_registered_end_date,
    booking_info_scheduling_week AS scheduling_week,
    csat_info_count_csat AS total_csat_response,
    CASE
      WHEN (
        DATE(inspector_control_inspector_registered_end_date) > (
          DATE_ADD(DATE(booking_info_scheduling_week), 6)
        )
        AND DATE(inspector_control_inspector_registered_start_date) <= DATE(booking_info_scheduling_week)
      )
      OR inspector_control_inspector_registered_end_date IS NULL
      THEN 1
      ELSE 0
    END AS ativo,
    SUM(fechamento_agenda_vt_em_d0_e_d_1_entrada) AS fechamento_agenda_d0_entrada,
    COALESCE(
      SUM(fechamento_agenda_vt_em_d0_e_d_1_entrada) / CAST(NULLIF(SUM(inspections_entrance_inspections_booked), 0) AS DOUBLE),
      0
    ) AS p_fechamento_agenda_d0_entrada,
    SUM(fechamento_agenda_vt_em_d0_e_d_1_saida) AS fechamento_agenda_d0_saida,
    COALESCE(
      SUM(fechamento_agenda_vt_em_d0_e_d_1_saida) / CAST(NULLIF(SUM(inspections_exit_inspections_booked), 0) AS DOUBLE),
      0
    ) AS p_fechamento_agenda_d0_saida,
    SUM(cancel_em_d0_entrada) AS cancel_d0_entrada,
    COALESCE(
      SUM(cancel_em_d0_entrada) / CAST(NULLIF(SUM(inspections_entrance_inspections_booked), 0) AS DOUBLE),
      0
    ) AS p_cancel_d0_entrada,
    SUM(cancel_em_d0_saida) AS cancel_d0_saida,
    COALESCE(
      SUM(cancel_em_d0_saida) / CAST(NULLIF(SUM(inspections_entrance_inspections_booked), 0) AS DOUBLE),
      0
    ) AS p_cancel_d0_saida,
    SUM(sync_in_24h_entranda) AS sync_in_24h_entranda,
    COALESCE(
      SUM(sync_in_24h_entranda) / CAST(NULLIF(SUM(inspections_entrance_inspections_done), 0) AS DOUBLE),
      0
    ) AS p_sync_in_24h_entranda,
    SUM(sync_in_24h_saida) AS sync_in_24h_saida,
    COALESCE(
      SUM(sync_in_24h_saida) / CAST(NULLIF(SUM(inspections_entrance_inspections_booked), 0) AS DOUBLE),
      0
    ) AS p_sync_in_24h_saida,
    SUM(no_show_entrada) AS no_show_entrada,
    COALESCE(
      SUM(no_show_entrada) / CAST(NULLIF(SUM(inspections_cancelada_entrada), 0) AS DOUBLE),
      0
    ) AS p_no_show_entrada,
    SUM(no_show_saida) AS no_show_saida,
    COALESCE(
      SUM(no_show_saida) / CAST(NULLIF(SUM(inspections_cancelada_saida), 0) AS DOUBLE),
      0
    ) AS p_no_show_saida,
    COALESCE(SUM(count_dsat_tags) / CAST(NULLIF(SUM(csat_info_count_csat), 0) AS DOUBLE), 0) AS dsat_tags,
    SUM(inspections_entrance_inspections_done) AS vistorias_feitas_entrada,
    COALESCE(
      SUM(inspections_entrance_inspections_done) / CAST(NULLIF(SUM(inspections_entrance_inspections_booked), 0) AS DOUBLE),
      0
    ) AS p_vistorias_feitas_entrada,
    SUM(inspections_exit_inspections_done) AS vistorias_feitas_saida,
    COALESCE(
      SUM(inspections_exit_inspections_done) / CAST(NULLIF(SUM(inspections_exit_inspections_booked), 0) AS DOUBLE),
      0
    ) AS p_vistorias_feitas_saida
  FROM base
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10
), rank_base AS (
  SELECT
    sk_inspector,
    inspector_name,
    inspector_email,
    inspector_company,
    regional_inspection,
    city_name,
    inspector_registered_start_date,
    inspector_registered_end_date,
    scheduling_week,
    ativo,
    fechamento_agenda_d0_entrada,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY fechamento_agenda_d0_entrada NULLS LAST) AS rank_fechamento_agenda_d0_entrada,
    p_fechamento_agenda_d0_entrada,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY p_fechamento_agenda_d0_entrada NULLS LAST) AS rank_p_fechamento_agenda_d0_entrada,
    fechamento_agenda_d0_saida,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY fechamento_agenda_d0_saida NULLS LAST) AS rank_fechamento_agenda_d0_saida,
    p_fechamento_agenda_d0_saida,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY p_fechamento_agenda_d0_saida NULLS LAST) AS rank_p_fechamento_agenda_d0_saida,
    cancel_d0_entrada,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY cancel_d0_entrada NULLS LAST) AS rank_cancel_d0_entrada,
    p_cancel_d0_entrada,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY p_cancel_d0_entrada NULLS LAST) AS rank_p_cancel_d0_entrada,
    cancel_d0_saida,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY cancel_d0_saida NULLS LAST) AS rank_cancel_d0_saida,
    p_cancel_d0_saida,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY p_cancel_d0_saida NULLS LAST) AS rank_p_cancel_d0_saida,
    sync_in_24h_entranda,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY sync_in_24h_entranda NULLS LAST) AS rank_sync_in_24h_entranda,
    p_sync_in_24h_entranda,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY p_sync_in_24h_entranda NULLS LAST) AS rank_p_sync_in_24h_entranda,
    sync_in_24h_saida,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY sync_in_24h_saida NULLS LAST) AS rank_sync_in_24h_saida,
    p_sync_in_24h_saida,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY p_sync_in_24h_saida NULLS LAST) AS rank_p_sync_in_24h_saida,
    no_show_entrada,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY no_show_entrada NULLS LAST) AS rank_no_show_entrada,
    p_no_show_entrada,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY p_no_show_entrada NULLS LAST) AS rank_p_no_show_entrada,
    no_show_saida,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY no_show_saida NULLS LAST) AS rank_no_show_saida,
    p_no_show_saida,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY p_no_show_saida NULLS LAST) AS rank_p_no_show_saida,
    vistorias_feitas_entrada,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY vistorias_feitas_entrada NULLS LAST) AS rank_vistorias_feitas_entrada,
    p_vistorias_feitas_entrada,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY p_vistorias_feitas_entrada NULLS LAST) AS rank_p_vistorias_feitas_entrada,
    vistorias_feitas_saida,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY vistorias_feitas_saida NULLS LAST) AS rank_vistorias_feitas_saida,
    p_vistorias_feitas_saida,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY p_vistorias_feitas_saida NULLS LAST) AS rank_p_vistorias_feitas_saida,
    dsat_tags,
    PERCENT_RANK() OVER (PARTITION BY scheduling_week, regional_inspection, city_name ORDER BY dsat_tags DESC) AS rank_dsat_tags,
    total_csat_response
  FROM indicadores
), validate_notas AS (
  SELECT
    sk_inspector,
    inspector_name,
    inspector_email,
    inspector_company,
    regional_inspection,
    city_name,
    inspector_registered_start_date,
    inspector_registered_end_date,
    scheduling_week,
    ativo,
    CASE
      WHEN ativo = 1 AND rank_fechamento_agenda_d0_entrada >= 0.7
      THEN 0
      WHEN ativo = 1 AND rank_fechamento_agenda_d0_entrada >= 0.1
      THEN 1.75
      ELSE 2.5
    END AS nota_v_fad0_on,
    CASE
      WHEN ativo = 1 AND rank_p_fechamento_agenda_d0_entrada >= 0.7
      THEN 0
      WHEN ativo = 1 AND rank_p_fechamento_agenda_d0_entrada >= 0.1
      THEN 1.75
      ELSE 2.5
    END AS nota_p_fad0_on,
    CASE
      WHEN ativo = 1 AND rank_fechamento_agenda_d0_saida >= 0.7
      THEN 0
      WHEN ativo = 1 AND rank_fechamento_agenda_d0_saida >= 0.1
      THEN 1.75
      ELSE 2.5
    END AS nota_v_fad0_off,
    CASE
      WHEN ativo = 1 AND rank_p_fechamento_agenda_d0_saida >= 0.7
      THEN 0
      WHEN ativo = 1 AND rank_p_fechamento_agenda_d0_saida >= 0.1
      THEN 1.75
      ELSE 2.5
    END AS nota_p_fad0_off,
    CASE
      WHEN ativo = 1 AND rank_cancel_d0_entrada >= 0.7
      THEN 0
      WHEN ativo = 1 AND rank_cancel_d0_entrada >= 0.1
      THEN 1.75
      ELSE 2.5
    END AS nota_v_canceld0_on,
    CASE
      WHEN ativo = 1 AND rank_p_cancel_d0_entrada >= 0.7
      THEN 0
      WHEN ativo = 1 AND rank_p_cancel_d0_entrada >= 0.1
      THEN 1.75
      ELSE 2.5
    END AS nota_p_canceld0_on,
    CASE
      WHEN ativo = 1 AND rank_cancel_d0_saida >= 0.7
      THEN 0
      WHEN ativo = 1 AND rank_cancel_d0_saida >= 0.1
      THEN 1.75
      ELSE 2.5
    END AS nota_v_canceld0_off,
    CASE
      WHEN ativo = 1 AND rank_p_cancel_d0_saida >= 0.7
      THEN 0
      WHEN ativo = 1 AND rank_p_cancel_d0_saida >= 0.1
      THEN 1.75
      ELSE 2.5
    END AS nota_p_canceld0_off,
    CASE
      WHEN ativo = 1 AND rank_vistorias_feitas_entrada >= 0.7
      THEN 2.5
      WHEN ativo = 1 AND rank_vistorias_feitas_entrada >= 0.1
      THEN 1.75
      ELSE 0
    END AS nota_volume_vf_on,
    CASE
      WHEN ativo = 1 AND rank_p_vistorias_feitas_entrada >= 0.7
      THEN 2.5
      WHEN ativo = 1 AND rank_p_vistorias_feitas_entrada >= 0.1
      THEN 1.75
      ELSE 0
    END AS nota_conversion_vf_on,
    CASE
      WHEN ativo = 1 AND rank_vistorias_feitas_saida >= 0.7
      THEN 2.5
      WHEN ativo = 1 AND rank_vistorias_feitas_saida >= 0.1
      THEN 1.75
      ELSE 0
    END AS nota_volume_vf_off,
    CASE
      WHEN ativo = 1 AND rank_p_vistorias_feitas_saida >= 0.7
      THEN 2.5
      WHEN ativo = 1 AND rank_p_vistorias_feitas_saida >= 0.1
      THEN 1.75
      ELSE 0
    END AS nota_conversion_vf_off,
    CASE
      WHEN ativo = 1 AND rank_sync_in_24h_entranda >= 0.7
      THEN 2.5
      WHEN ativo = 1 AND rank_sync_in_24h_entranda >= 0.1
      THEN 1.75
      ELSE 0
    END AS nota_v_sync_on,
    CASE
      WHEN ativo = 1 AND rank_p_sync_in_24h_entranda >= 0.7
      THEN 2.5
      WHEN ativo = 1 AND rank_p_sync_in_24h_entranda >= 0.1
      THEN 1.75
      ELSE 0
    END AS nota_p_sync_on,
    CASE
      WHEN ativo = 1 AND rank_sync_in_24h_saida >= 0.7
      THEN 2.5
      WHEN ativo = 1 AND rank_sync_in_24h_saida >= 0.1
      THEN 1.75
      ELSE 0
    END AS nota_v_sync_off,
    CASE
      WHEN ativo = 1 AND rank_p_sync_in_24h_saida >= 0.7
      THEN 2.5
      WHEN ativo = 1 AND rank_p_sync_in_24h_saida >= 0.1
      THEN 1.75
      ELSE 0
    END AS nota_p_sync_off,
    CASE
      WHEN ativo = 1 AND rank_no_show_entrada <= 0.1
      THEN 1.75
      WHEN ativo = 1 AND rank_no_show_entrada <= 0.7
      THEN 2.5
      ELSE 0
    END AS nota_no_show_on,
    CASE
      WHEN ativo = 1 AND rank_p_no_show_entrada <= 0.1
      THEN 1.75
      WHEN ativo = 1 AND rank_p_no_show_entrada <= 0.7
      THEN 2.5
      ELSE 0
    END AS nota_p_no_show_on,
    CASE
      WHEN ativo = 1 AND rank_no_show_saida <= 0.1
      THEN 1.75
      WHEN ativo = 1 AND rank_no_show_saida <= 0.7
      THEN 2.5
      ELSE 0
    END AS nota_v_no_show_off,
    CASE
      WHEN ativo = 1 AND rank_p_no_show_saida <= 0.1
      THEN 1.75
      WHEN ativo = 1 AND rank_p_no_show_saida <= 0.7
      THEN 2.5
      ELSE 0
    END AS nota_p_no_show_off,
    CASE
      WHEN total_csat_response < 5
      THEN NULL
      WHEN ativo = 1 AND rank_dsat_tags >= 0.7
      THEN 10
      WHEN ativo = 1 AND rank_dsat_tags >= 0.1
      THEN 7
      ELSE 0
    END AS nota_dsat_tags,
    total_csat_response
  FROM rank_base
), score AS (
  SELECT
    sk_inspector,
    inspector_name,
    inspector_email,
    inspector_company,
    regional_inspection,
    city_name,
    inspector_registered_start_date,
    inspector_registered_end_date,
    scheduling_week,
    ativo,
    (
      (
        nota_v_fad0_on + nota_p_fad0_on
      ) * 0.8
    ) + (
      (
        nota_v_fad0_off + nota_p_fad0_off
      ) * 1.2
    ) AS nota_fechamento_agenda_d0,
    (
      (
        nota_v_canceld0_on + nota_p_canceld0_on
      ) * 0.8
    ) + (
      (
        nota_v_canceld0_off + nota_p_canceld0_off
      ) * 1.2
    ) AS nota_cancel_d0,
    (
      (
        nota_volume_vf_on + nota_conversion_vf_on
      ) * 0.8
    ) + (
      (
        nota_volume_vf_off + nota_conversion_vf_off
      ) * 1.2
    ) AS nota_conversao,
    (
      (
        nota_v_sync_on + nota_p_sync_on
      ) * 1.0
    ) + (
      (
        nota_v_sync_off + nota_p_sync_off
      ) * 1.0
    ) AS nota_sync,
    (
      (
        nota_no_show_on + nota_p_no_show_on
      ) * 0.8
    ) + (
      (
        nota_v_no_show_off + nota_p_no_show_off
      ) * 1.2
    ) AS nota_no_show,
    nota_dsat_tags,
    total_csat_response
  FROM validate_notas
), sql_inspections_window_function AS (
  SELECT
    public_dim_contract.sk_contract AS sk_contract,
    inspections.sk_inspection,
    booking_info.sk_booking,
    DATE(public_dim_contract.ts_signature) AS dt_signature,
    DATE(public_dim_contract.ts_created) AS dt_created_contract,
    DATE(contract_termination.ts_created) AS dt_created_termination,
    DATE(booking_info.ts_created_local) AS booking_created,
    booking_info.ts_scheduling_local AS scheduling_date,
    booking_info.dt_scheduling AS scheduling_local,
    DATE(
      TO_TIMESTAMP(CAST(NULLIF(inspection_dates.sk_booking_cancelled_date, -1) AS STRING), 'yyyyMMdd')
    ) AS cancellation_date,
    DATE(
      TO_TIMESTAMP(CAST(NULLIF(inspection_dates.sk_inspected_date, -1) AS STRING), 'yyyyMMdd')
    ) AS inspection_date,
    inspections.ts_first_synced AS first_synced_date,
    DATE(public_dim_contract.dt_entrance) AS dt_entrance_date,
    DATE(contract_termination.dt_termination) AS termination_date,
    CASE
      WHEN inspections.status = 'Cancelada'
      THEN LEAD(DATE(booking_info.ts_created_local)) OVER (PARTITION BY public_dim_contract.sk_contract, inspections.type ORDER BY booking_info.sk_booking NULLS LAST)
      ELSE NULL
    END AS next_booking_created,
    LAG(DATE(booking_info.ts_scheduling_local)) OVER (PARTITION BY public_dim_contract.sk_contract, inspections.type ORDER BY booking_info.sk_booking NULLS LAST) AS last_scheduling,
    LAG(
      DATE(
        TO_TIMESTAMP(CAST(NULLIF(inspection_dates.sk_booking_cancelled_date, -1) AS STRING), 'yyyyMMdd')
      )
    ) OVER (PARTITION BY public_dim_contract.sk_contract, inspections.type ORDER BY booking_info.sk_booking NULLS LAST) AS last_cancel,
    RANK() OVER (PARTITION BY public_dim_contract.sk_contract, inspections.type ORDER BY inspections.sk_inspection NULLS LAST) AS number_booking,
    inspections.type AS inspections_type,
    inspections.status AS status,
    public_dim_contract.status AS contract_status,
    contract_termination.status AS cotract_termination_status,
    mis.max_status,
    contract_termination.has_exit_inspection
  FROM dw_public.dim_inspection AS inspections
  LEFT JOIN dw_public.fact_inspection_bookings AS inspection_dates
    ON inspection_dates.sk_inspection = inspections.sk_inspection
  LEFT JOIN dw_public.dim_booking AS booking_info
    ON inspection_dates.sk_booking = booking_info.sk_booking
    AND booking_info.type IN ('Vistoria', 'VistoriaQuarteirizada')
  LEFT JOIN dw_rent.dim_contract AS public_dim_contract
    ON public_dim_contract.sk_contract = inspection_dates.sk_contract
  LEFT JOIN first_termination AS first_termination
    ON first_termination.id_contract = public_dim_contract.sk_contract
  LEFT JOIN datalake_offboarding.contract_termination AS contract_termination
    ON contract_termination.id_termination = first_termination.max_termination
  LEFT JOIN max_inspection_status AS mis
    ON mis.sk_contract = public_dim_contract.sk_contract AND mis.type = inspections.type
), sql_inspection_csat AS (
  SELECT DISTINCT
    id_contract,
    email,
    LAST_VALUE(improvement_tags) OVER (PARTITION BY id_contract ORDER BY ts_submitted NULLS LAST rows BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS improvement_tags,
    LAST_VALUE(comments) OVER (PARTITION BY id_contract ORDER BY ts_submitted NULLS LAST rows BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS comments,
    CAST(LAST_VALUE(general_satisfaction_evaluation) OVER (PARTITION BY id_contract ORDER BY ts_submitted NULLS LAST rows BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS DOUBLE) AS general_satisfaction_evaluation,
    MAX(ts_submitted) OVER (PARTITION BY id_contract) AS ts_submitted,
    'Proprietario' AS role,
    'Entrada' AS inspection_type
  FROM datalake_gsheets_clean.owner_entrance_inspection_csat
  UNION
  SELECT DISTINCT
    id_contract,
    email,
    LAST_VALUE(improvement_tags) OVER (PARTITION BY id_contract ORDER BY ts_submitted NULLS LAST rows BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS improvement_tags,
    LAST_VALUE(comments) OVER (PARTITION BY id_contract ORDER BY ts_submitted NULLS LAST rows BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS comments,
    CAST(LAST_VALUE(general_satisfaction_evaluation) OVER (PARTITION BY id_contract ORDER BY ts_submitted NULLS LAST rows BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS DOUBLE) AS general_satisfaction_evaluation,
    MAX(ts_submitted) OVER (PARTITION BY id_contract) AS ts_submitted,
    'Proprietario' AS role,
    'Saida' AS inspection_type
  FROM datalake_gsheets_clean.owner_exit_inspection_csat
  UNION
  SELECT DISTINCT
    id_contract,
    email,
    LAST_VALUE(improvement_tags) OVER (PARTITION BY id_contract ORDER BY ts_submitted NULLS LAST rows BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS improvement_tags,
    LAST_VALUE(comments) OVER (PARTITION BY id_contract ORDER BY ts_submitted NULLS LAST rows BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS comments,
    CAST(LAST_VALUE(general_satisfaction_evaluation) OVER (PARTITION BY id_contract ORDER BY ts_submitted NULLS LAST rows BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS DOUBLE) AS general_satisfaction_evaluation,
    MAX(ts_submitted) OVER (PARTITION BY id_contract) AS ts_submitted,
    'Inquilino' AS role,
    'Entrada' AS inspection_type
  FROM datalake_gsheets_clean.tenant_entrance_inspection_csat
), first_termination AS (
  SELECT
    id_contract,
    MAX(id_termination) AS max_termination
  FROM datalake_offboarding.contract_termination
  GROUP BY
    1
), max_inspection_status AS (
  SELECT
    sk_contract,
    inspections.type,
    MAX(
      CASE
        WHEN status IN ('Revisada', 'Finalizada', 'Comentada', 'EmRevisao')
        THEN 1
        ELSE 0
      END
    ) AS max_status
  FROM dw_public.dim_inspection AS inspections
  INNER JOIN dw_public.fact_inspection_bookings AS inspection_dates
    ON inspection_dates.sk_inspection = inspections.sk_inspection
  GROUP BY
    1,
    2
)
SELECT
  s.sk_inspector,
  s.inspector_name,
  s.inspector_email,
  s.inspector_company,
  s.regional_inspection,
  s.city_name,
  s.inspector_registered_start_date,
  s.inspector_registered_end_date,
  s.scheduling_week,
  s.ativo,
  s.nota_fechamento_agenda_d0,
  s.nota_cancel_d0,
  s.nota_conversao,
  s.nota_sync,
  s.nota_no_show,
  s.nota_dsat_tags,
  ind.fechamento_agenda_d0_entrada,
  ind.p_fechamento_agenda_d0_entrada,
  ind.fechamento_agenda_d0_saida,
  ind.p_fechamento_agenda_d0_saida,
  ind.cancel_d0_entrada,
  ind.p_cancel_d0_entrada,
  ind.cancel_d0_saida,
  ind.p_cancel_d0_saida,
  ind.sync_in_24h_entranda,
  ind.p_sync_in_24h_entranda,
  ind.sync_in_24h_saida,
  ind.p_sync_in_24h_saida,
  ind.no_show_entrada,
  ind.p_no_show_entrada,
  ind.no_show_saida,
  ind.p_no_show_saida,
  ind.dsat_tags,
  ind.vistorias_feitas_entrada,
  ind.p_vistorias_feitas_entrada,
  ind.vistorias_feitas_saida,
  ind.p_vistorias_feitas_saida,
  s.total_csat_response
FROM score AS s
LEFT JOIN indicadores AS ind
  ON s.sk_inspector = ind.sk_inspector
  AND s.city_name = ind.city_name
  AND s.scheduling_week = ind.scheduling_week