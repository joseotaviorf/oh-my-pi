WITH fact_visits AS (
  WITH drop_reason_name_table AS (
    SELECT
      -- IDs
        db.id_visitor AS id_buyer,
        vb.sk_booking,
        vb.sk_house,
        vb.sk_agent,
        fo.sk_offer,
        vb.sk_user_agent,
        vb.sk_user_cancelation,

        -- Visit
        db.dt_scheduling,
        dd.week_start AS week,
        vb.sk_booking_created_date,
        vb.sk_visit_completed_date,
        vb.is_virtual_visit,
        db.status,
        db.first_update_source,
        ROW_NUMBER() OVER (PARTITION BY db.id_visitor ORDER BY db.dt_scheduling, db.dt_created) AS buyer_rw,

        -- Visit Cancellation
        db.cancellation_reason_category,
        db.troublesome_entrance,
        db.agent_arrived,

        -- Offer
        fo.sk_offer_submitted_date,
        fo.sk_offer_accepted_date,
      CASE
            WHEN drop_reason IS NULL AND sk_offer_dismissed_date IS NULL THEN ''
            WHEN LENGTH(drop_reason) > 4 THEN drop_reason
            WHEN drop_reason = 1 THEN 'Buyer - pagamento envolve permuta'
            WHEN drop_reason = 2 THEN 'Buyer - pagamento envolve aluguel investido'
            WHEN drop_reason = 3 THEN 'Buyer - pagamento parcelado'
            WHEN drop_reason = 4 THEN 'Buyer - não tem dinheiro para a entrada de qualquer imóvel'
            WHEN drop_reason = 5 THEN 'Buyer - não aceita modelo 5A'
            WHEN drop_reason = 7 THEN 'Buyer - não aceitou a contraproposta do Seller'
            WHEN drop_reason = 8 THEN 'Buyer - vai procurar outro imóvel'
            WHEN drop_reason = 9 THEN 'Buyer - pediu para desconsiderar a proposta'
            WHEN drop_reason = 10 THEN 'Buyer - nunca atende'
            WHEN drop_reason = 11 THEN 'Seller - demora para retornar'
            WHEN drop_reason = 11 THEN 'Buyer - demora para retornar'
            WHEN drop_reason = 12 THEN 'Seller - não aceitou proposta do buyer (sem contraproposta)'
            WHEN drop_reason = 13 THEN 'Buyer - desistiu de comprar qualquer imóvel'
            WHEN drop_reason = 14 THEN 'Seller - não aceitou contraproposta do buyer'
            WHEN drop_reason = 15 THEN 'Buyer - já alugou ou comprou com outra imobiliária'
            WHEN drop_reason = 16 THEN 'Seller - problemas de documentação do Imóvel'
            WHEN drop_reason = 17 THEN 'Seller - condições legais (que não a documentação do Imóvel)'
            WHEN drop_reason = 18 THEN 'Seller - vendeu por outra imobiliária'
            WHEN drop_reason = 19 THEN 'Seller - alugou ou vai alugar o imóvel'
            WHEN drop_reason = 20 THEN 'Seller - não vai mais vender o imóvel'
            WHEN drop_reason = 102 THEN 'Seller - nunca atende'
            WHEN drop_reason = 103 THEN 'Seller - demora para retornar'
            WHEN drop_reason = 104 THEN 'Seller - não aceita modelo 5A'
            WHEN drop_reason = 105 THEN 'Seller - problemas para visitar o imóvel'
            WHEN drop_reason = 106 THEN 'Seller - IQ dificultou processo de venda'
            WHEN drop_reason = 107 THEN 'Buyer - não tem dinheiro para a entrada (deste imóvel)'
            WHEN drop_reason = 108 THEN 'Seller - anúncio com valor incorreto'
            WHEN drop_reason = 109 THEN 'Seller - seller é PJ'
            WHEN drop_reason = 110 THEN 'Buyer - comprou outro imóvel pelo 5A'
            WHEN drop_reason = 111 THEN 'Seller - vendeu pelo 5A para outro buyer'
            WHEN drop_reason = 112 THEN 'Buyer - problemas de documentação'
            WHEN drop_reason = 113 THEN 'Buyer - financiamento do Buyer não cobre o do Seller'
            WHEN drop_reason = 114 THEN 'Seller - não aceita pagamento financiado'
            WHEN drop_reason = 115 THEN 'Buyer - desconto maior do que 30%'
            WHEN drop_reason = 116 THEN 'Buyer - pediu para desconsiderar a proposta'
            WHEN drop_reason = 117 THEN 'Buyer - Proposta aceita invalidada'
            WHEN drop_reason = 118 THEN 'Seller - Proposta aceita invalidada'
            ELSE 'ERRO'
        END AS drop_reason_name,

        -- CCV
        fo.sk_sale_agreement_signed_date,

        -- House Registry
        sa.ts_house_registry_ended,

        -- Region
        dr.name AS region_name,
        CASE
            WHEN db.dt_created <= '2021-03-07'::date THEN
                CASE
                    WHEN dr.region_code IN ('SPO 01','SPO 10') THEN 'SPO 01'
                    WHEN dr.region_code IN ('SPO 02', 'SPO 03') THEN 'SPO 02'
                    WHEN dr.region_code = 'SPO 04' THEN 'SPO 03'
                    WHEN dr.region_code = 'SPO 05' THEN 'SPO 04'
                    WHEN dr.region_code IN ('SPO 06', 'SPO 07') THEN 'SPO 05'
                    WHEN dr.region_code = 'SPO 08' THEN 'SPO 04'
                    WHEN dr.region_code IN ('SPO 09','SPO 11') THEN 'SPO 06'
                    WHEN dr.region_code = 'RIO 01' THEN 'RIO 01'
                    WHEN dr.region_code = 'RIO 02' THEN 'RIO 02'
                    WHEN dr.region_code = 'RIO 03' THEN 'RIO 03'
                    WHEN dr.region_code = 'RIO 04' THEN 'RIO 04'
                    WHEN dr.region_code IN ('RIO 05', 'RIO 06') THEN 'RIO 05'
                    WHEN dr.region_code IN ('RIO 07', 'RIO 10') THEN 'RIO 07'
                    WHEN dr.region_code = 'RIO 08' THEN 'RIO 06'
                    WHEN dr.region_code = 'RIO 09' THEN 'RIO 08'
                    WHEN dr.region_code = 'RIO 11' THEN 'RIO 09'
                    WHEN dr.region_code IN ('STA 01', 'SBE 01', 'SCA 01', 'DIA 01') THEN 'ABC'
                    ELSE dr.region_code
                END
            ELSE dr.region_code
        END AS region_code,

        -- Visit Review
        br.agent_performance,
        br.does_want_same_agent

    FROM dw_sale.fact_visits AS vb
    LEFT JOIN
        dw_sale.fact_offers AS fo
            ON fo.sk_booking = vb.sk_booking
    LEFT JOIN
        dw_sale.dim_offer AS dof
            ON dof.sk_offer = fo.sk_offer
    LEFT JOIN
        dw_public.dim_booking AS db
            ON db.sk_booking = vb.sk_booking
    LEFT JOIN
        dw_public.dim_tenant_booking_review AS br
            ON br.sk_tenant_booking_review = vb.sk_booking
    LEFT JOIN
        dw_public.dim_region AS dr
            ON vb.sk_region = dr.sk_region
    LEFT JOIN
        dw_public.dim_date AS dd
            ON db.dt_scheduling::date = dd.date
    LEFT JOIN
        dw_sale.dim_sale_agreement AS sa
            ON sa.sk_offer = fo.sk_offer
    WHERE vb.sk_agent > 0
  )
    SELECT
        -- IDs
        db.id_visitor AS id_buyer,
        vb.sk_booking,
        vb.sk_house,
        vb.sk_agent,
        fo.sk_offer,
        vb.sk_user_agent,
        vb.sk_user_cancelation,

        -- Visit
        db.dt_scheduling,
        dd.week_start AS week,
        vb.sk_booking_created_date,
        vb.sk_visit_completed_date,
        vb.is_virtual_visit,
        db.status,
        db.first_update_source,
        db.dt_created,
        ROW_NUMBER() OVER (PARTITION BY db.id_visitor ORDER BY db.dt_scheduling, db.dt_created) AS buyer_rw,

        -- Visit Cancellation
        db.cancellation_reason_category,
        db.troublesome_entrance,
        db.agent_arrived,

        -- Offer
        fo.sk_offer_submitted_date,
        fo.sk_offer_accepted_date,
        drn.drop_reason_name,
        CASE
            WHEN drop_reason IS NULL AND sk_offer_dismissed_date IS NULL THEN ''
            WHEN drn.drop_reason_name = 'Buyer - pediu para desconsiderar a proposta' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer - nunca atende' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Seller - nunca atende' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer - Proposta inválida' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer - Proposta sem visita' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer Não Qualificado' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Imóvel - IQ Morando' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer - problemas de documentação' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Seller - problemas de documentação do Imóvel' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Imóvel - Diligência' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Seller - anúncio com valor incorreto' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Seller - seller é PJ' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer - desconto maior do que 30%' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer - não tem dinheiro para a entrada (deste imóvel)' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer - não tem dinheiro para a entrada de qualquer imóvel' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer - pagamento envolve aluguel investido' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer - pagamento envolve permuta' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer - pagamento parcelado' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Buyer - Condição de Pagamento' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Seller - vendeu pelo 5A para outro buyer' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Seller - IQ dificultou processo de venda' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Seller - problemas para visitar o imóvel' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Buyer - já alugou ou comprou com outra imobiliária' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Seller - vendeu por outra imobiliária' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Seller - condições legais (que não a documentação do Imóvel)' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Buyer - financiamento do Buyer não cobre o do Seller' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Buyer - não aceita modelo 5A' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Seller - não aceita modelo 5A' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Buyer - comprou outro imóvel pelo 5A' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Buyer - não aceitou a contraproposta do Seller' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Seller - não aceita pagamento financiado' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Seller - não aceitou contraproposta do buyer' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Seller - não aceitou proposta do buyer (sem contraproposta)' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Valor de desconto - Com Contra' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Valor de desconto - Sem Contra' THEN 'Quali'
            WHEN drn.drop_reason_name = 'COVID19' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Buyer - demora para retornar' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Buyer - desistiu de comprar qualquer imóvel' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Buyer - vai procurar outro imóvel' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Seller - alugou ou vai alugar o imóvel' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Seller - demora para retornar' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Seller - não vai mais vender o imóvel' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Buyer desistiu de comprar (esse imóvel)' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Buyer Expirado - Ainda Procurando' THEN 'Quali'
            WHEN drn.drop_reason_name = 'Buyer - Proposta aceita invalidada' THEN 'Não Quali'
            WHEN drn.drop_reason_name = 'Seller - Proposta aceita invalidada' THEN 'Não Quali'
            ELSE 'ERRO'
        END AS drop_category,

        -- CCV
        fo.sk_sale_agreement_signed_date,

        -- House Registry
        sa.ts_house_registry_ended,

        -- Region
        dr.name AS region_name,
        CASE
            WHEN db.dt_created <= '2021-03-07'::date THEN
                CASE
                    WHEN dr.region_code IN ('SPO 01','SPO 10') THEN 'SPO 01'
                    WHEN dr.region_code IN ('SPO 02', 'SPO 03') THEN 'SPO 02'
                    WHEN dr.region_code = 'SPO 04' THEN 'SPO 03'
                    WHEN dr.region_code = 'SPO 05' THEN 'SPO 04'
                    WHEN dr.region_code IN ('SPO 06', 'SPO 07') THEN 'SPO 05'
                    WHEN dr.region_code = 'SPO 08' THEN 'SPO 04'
                    WHEN dr.region_code IN ('SPO 09','SPO 11') THEN 'SPO 06'
                    WHEN dr.region_code = 'RIO 01' THEN 'RIO 01'
                    WHEN dr.region_code = 'RIO 02' THEN 'RIO 02'
                    WHEN dr.region_code = 'RIO 03' THEN 'RIO 03'
                    WHEN dr.region_code = 'RIO 04' THEN 'RIO 04'
                    WHEN dr.region_code IN ('RIO 05', 'RIO 06') THEN 'RIO 05'
                    WHEN dr.region_code IN ('RIO 07', 'RIO 10') THEN 'RIO 07'
                    WHEN dr.region_code = 'RIO 08' THEN 'RIO 06'
                    WHEN dr.region_code = 'RIO 09' THEN 'RIO 08'
                    WHEN dr.region_code = 'RIO 11' THEN 'RIO 09'
                    WHEN dr.region_code IN ('STA 01', 'SBE 01', 'SCA 01', 'DIA 01') THEN 'ABC'
                    ELSE dr.region_code
                END
            ELSE dr.region_code
        END AS region_code,

        -- Visit Review
        br.agent_performance,
        br.does_want_same_agent

    FROM dw_sale.fact_visits AS vb
    LEFT JOIN
        dw_sale.fact_offers AS fo
            ON fo.sk_booking = vb.sk_booking
    LEFT JOIN
        dw_sale.dim_offer AS dof
            ON dof.sk_offer = fo.sk_offer
    LEFT JOIN
        dw_public.dim_booking AS db
            ON db.sk_booking = vb.sk_booking
    LEFT JOIN
        dw_public.dim_tenant_booking_review AS br
            ON br.sk_tenant_booking_review = vb.sk_booking
    LEFT JOIN
        dw_public.dim_region AS dr
            ON vb.sk_region = dr.sk_region
    LEFT JOIN
        dw_public.dim_date AS dd
            ON db.dt_scheduling::date = dd.date
    LEFT JOIN
        dw_sale.dim_sale_agreement AS sa
            ON sa.sk_offer = fo.sk_offer
    LEFT JOIN
        drop_reason_name_table AS drn
            ON dof.sk_offer = drn.sk_offer
    WHERE vb.sk_agent > 0
),
buyer_nps AS (

    WITH nps AS (
        SELECT
            fv.sk_agent,
            dd.week_start AS week,
            fnd.sk_user,
            dna.score_category,
            fnd.score
        FROM dw_tracksale.fact_nps_dispatches AS fnd
        JOIN
            dw_tracksale.dim_nps_answer AS dna
                ON dna.sk_nps_answer  = fnd.sk_nps_answer
        LEFT JOIN
            dw_tracksale.dim_nps_campaign AS dnc
                ON dnc.sk_nps_campaign  = fnd.sk_nps_campaign
        LEFT JOIN
            dw_sale.fact_visits AS fv
                ON fv.sk_booking = fnd.sk_booking
        LEFT JOIN
            dw_public.dim_booking AS db
                ON db.sk_booking = fv.sk_booking
        LEFT JOIN
            dw_public.dim_date AS dd
                ON DATE(db.dt_scheduling) = dd.date
        WHERE dnc.customer_type  = 'buyer'
    ),
    nps_metrics AS (
      SELECT
        sk_agent,
        week,
        COUNT(DISTINCT sk_user) AS b_nps_answers,
        COUNT(DISTINCT CASE WHEN score_category ='promoter' THEN sk_user END) AS b_promoters,
        COUNT(DISTINCT CASE WHEN score_category ='detractor' THEN sk_user END) AS b_detractors
    FROM nps
    GROUP BY 1, 2
    )
    SELECT
        nps.sk_agent,
        nps.week,
        COUNT(DISTINCT nps.sk_user) AS b_nps_answers,
        b_promoters,
        b_detractors,
        ((b_promoters*1.00 - b_detractors*1.00) / NULLIF(b_nps_answers*1.00,0))*100 AS avg_nps_score
    FROM nps
    LEFT JOIN
        nps_metrics
      ON
        nps.sk_agent = nps_metrics.sk_agent AND
        nps.week = nps_metrics.week
    GROUP BY 1, 2, 4, 5, 6
),
buyer AS (
    SELECT
        sk_booking,
        id_buyer,
        sk_agent,
        ROW_NUMBER() OVER (PARTITION BY sk_agent, id_buyer ORDER BY dt_scheduling, dt_created) AS vc_rw
    FROM fact_visits
    WHERE sk_visit_completed_date > 0
),
daily_agent_hours AS (
  SELECT
    fa.sk_agent,
    dslot.date,
    dslot.week_start AS week,
    CASE
        WHEN  dslot.date <= '2021-03-07'::date THEN
              CASE
                WHEN fa.area in ('SPO 01','SPO 10') THEN 'SPO 01'
                WHEN fa.area in ('SPO 02', 'SPO 03') THEN 'SPO 02'
                WHEN fa.area = 'SPO 04' THEN 'SPO 03'
                WHEN fa.area = 'SPO 05' THEN 'SPO 04'
                WHEN fa.area in ('SPO 06', 'SPO 07') THEN 'SPO 05'
                WHEN fa.area = 'SPO 08' THEN 'SPO 04'
                WHEN fa.area in ('SPO 09','SPO 11') THEN 'SPO 06'
                WHEN fa.area = 'RIO 01' THEN 'RIO 01'
                WHEN fa.area = 'RIO 02' THEN 'RIO 02'
                WHEN fa.area = 'RIO 03' THEN 'RIO 03'
                WHEN fa.area = 'RIO 04' THEN 'RIO 04'
                WHEN fa.area in ('RIO 05', 'RIO 06') THEN 'RIO 05'
                WHEN fa.area in ('RIO 07', 'RIO 10') THEN 'RIO 07'
                WHEN fa.area = 'RIO 08' THEN 'RIO 06'
                WHEN fa.area = 'RIO 09' THEN 'RIO 08'
                WHEN fa.area = 'RIO 11' THEN 'RIO 09'
                WHEN fa.area in ('STA 01', 'SBE 01', 'SCA 01', 'DIA 01') THEN 'ABC'
                ELSE fa.area
                END
              ELSE fa.area END AS region_code,
          fa.id_work_contract,
          CASE
              WHEN dslot.weekday_name = 'Monday' THEN 'Seg'
              WHEN dslot.weekday_name = 'Tuesday' THEN 'Ter'
              WHEN dslot.weekday_name = 'Wednesday' THEN 'Qua'
              WHEN dslot.weekday_name = 'Thursday' THEN 'Qui'
              WHEN dslot.weekday_name = 'Friday' THEN 'Sex'
              WHEN dslot.weekday_name = 'Saturday' THEN 'Sab'
              WHEN dslot.weekday_name = 'Sunday' THEN 'Dom'
          END AS weekdays,
          CAST(fa.allocated_slots_0/4 AS BIGINT) AS hours_available,
          CAST(fa.max_slots_allocation_available/4 AS BIGINT) AS total_hours
      FROM
          dw_agent.fact_agent_daily_allocations AS fa
      LEFT JOIN
          dw_public.dim_date AS dslot
              ON fa.sk_slot_date = dslot.sk_date
      WHERE dslot.year > 2019 AND fa.area != "-1"
),
weekly_region_agent_hours AS (
    SELECT
        week,
        sk_agent,
        region_code,
        SUM(hours_available) AS weekly_available_hours,
        SUM(total_hours) AS weekly_total_hours,
        ROW_NUMBER() OVER (PARTITION BY week, sk_agent ORDER BY SUM(hours_available) DESC) AS rw
    FROM daily_agent_hours
    GROUP BY 1, 2, 3
),
agent_region_week AS (
    SELECT
        week,
        sk_agent,
        region_code
    FROM weekly_region_agent_hours AS wrh
    WHERE rw = 1
),
weekly_agent_hours AS (
    WITH weekdays_with_hours_available AS (
        SELECT
         DISTINCT week,
          sk_agent,
          ROW_NUMBER() OVER (PARTITION BY sk_agent, week ORDER BY date DESC) AS rw,
          concat_ws("-",collect_list(weekdays) OVER (PARTITION BY sk_agent, week ORDER BY date)) AS weekdays_w_hours_available
        FROM daily_agent_hours as dah
        WHERE
          hours_available > 0
    ),
    weekdays_with_hours_available_rw_is_1 AS (
        SELECT
          week,
          sk_agent,
          weekdays_w_hours_available
        FROM weekdays_with_hours_available
        WHERE
          rw = 1
    )
    SELECT
        dah.week,
        dah.sk_agent,
        CASE
            WHEN wha.weekdays_w_hours_available = 'Seg-Ter-Qua-Qui-Sex-Sab-Dom' THEN 'Seg-à-Dom'
            WHEN wha.weekdays_w_hours_available = 'Seg-Ter-Qua-Qui-Sex-Sab' THEN 'Seg-à-Sab'
            WHEN wha.weekdays_w_hours_available = 'Seg-Ter-Qua-Qui-Sex' THEN 'Seg-à-Sex'
            ELSE wha.weekdays_w_hours_available
        END AS weekdays_w_hours_available,
        MAX(CASE WHEN dah.date <= dah.week THEN dah.id_work_contract END) AS id_work_contract,
        COUNT(DISTINCT CASE WHEN dah.hours_available > 0 THEN dah.date END) AS days_w_hours_available,
        SUM(dah.hours_available) AS weekly_available_hours,
        SUM(dah.total_hours) AS weekly_total_hours
    FROM
        daily_agent_hours AS dah
    LEFT JOIN
        weekdays_with_hours_available_rw_is_1 wha
            ON dah.week = wha.week
            AND dah.sk_agent = wha.sk_agent
    GROUP BY 1, 2, 3
),
count_per_agent_week AS (
    SELECT
        -- ID Agent-Week
        sf.sk_agent,
        sf.week,
        ROW_NUMBER() OVER (PARTITION BY sf.sk_agent ORDER BY sf.week) AS agent_week_order,

        -- Event Metrics
        -- Visits
        COUNT(DISTINCT CASE WHEN sf.sk_booking > 0 THEN sf.sk_booking END) AS bookings,
        COUNT(DISTINCT CASE WHEN sf.sk_booking > 0 AND sf.sk_booking_created_date IS NOT NULL AND sf.first_update_source = 'Corretores' THEN sf.sk_booking END) AS bookings_by_agent,
        COUNT(DISTINCT CASE WHEN sf.sk_visit_completed_date = -1 AND sf.sk_user_agent = sk_user_cancelation THEN sf.sk_booking END) AS visits_cancelled_by_agent,
        COUNT(DISTINCT CASE WHEN sf.sk_visit_completed_date = -1 AND sf.cancellation_reason_category = 'Agent' THEN sf.sk_booking END) AS visits_cancelled_agent_reason,
        COUNT(DISTINCT CASE WHEN sf.sk_visit_completed_date = -1 AND sf.cancellation_reason_category IS NULL AND sf.troublesome_entrance IS NULL AND sf.agent_arrived = 0 THEN sf.sk_booking END) AS no_show_by_agent,
        COUNT(DISTINCT CASE WHEN sf.status = 'Realizado' THEN sf.sk_booking END) AS visits_ended,
        COUNT(DISTINCT CASE WHEN sf.is_virtual_visit THEN sf.sk_booking END) AS virtual_visits,
        COUNT(DISTINCT CASE WHEN sf.sk_visit_completed_date > 0 THEN sf.sk_booking END) AS visits_completed,
        -- Offers
        COUNT(DISTINCT sf.sk_offer) AS offers_submitted,
        COUNT(DISTINCT CASE WHEN sf.drop_category = 'Quali' THEN sf.sk_offer END) AS offers_qualified,
        COUNT(DISTINCT CASE WHEN sf.sk_offer_accepted_date > 0 THEN sf.sk_offer END) AS offers_accepted,
        -- CCV›
        COUNT(DISTINCT CASE WHEN sf.sk_sale_agreement_signed_date > 0 THEN sf.sk_offer END) AS sales_agreements,
        -- House Registry
        COUNT(DISTINCT CASE WHEN sf.ts_house_registry_ended IS NOT NULL THEN sf.sk_offer END) AS house_registred,
        -- House Metrics
        COUNT(DISTINCT CASE WHEN sf.sk_booking_created_date > 0 THEN sf.sk_house END) AS houses_booked,
        COUNT(DISTINCT CASE WHEN sf.sk_visit_completed_date > 0 THEN sf.sk_house END) AS houses_visited,
        -- Buyer Metrics
        COUNT(DISTINCT CASE WHEN sf.sk_booking_created_date > 0 THEN sf.id_buyer END) AS b_vb,
        COUNT(DISTINCT CASE WHEN sf.sk_visit_completed_date > 0 THEN sf.id_buyer END) AS b_vc,
        COUNT(DISTINCT CASE WHEN sf.sk_offer_submitted_date > 0 THEN sf.id_buyer END) AS b_os,
        COUNT(DISTINCT CASE WHEN sf.drop_category = 'Quali' THEN sf.id_buyer END) AS b_oq,
        COUNT(DISTINCT CASE WHEN sf.sk_offer_accepted_date > 0 THEN sf.id_buyer END) AS b_oa,
        COUNT(DISTINCT CASE WHEN sf.sk_sale_agreement_signed_date > 0 THEN sf.id_buyer END) AS b_ccv,
        COUNT(DISTINCT CASE WHEN sf.ts_house_registry_ended IS NOT NULL THEN sf.id_buyer END) AS b_hr,

        -- New buyers
        COUNT(DISTINCT CASE WHEN sf.sk_booking_created_date > 0 AND buyer_rw = 1 THEN sf.id_buyer END) AS new_buyers,

        -- Buyer Recurrency
        COUNT(DISTINCT CASE WHEN sf.sk_visit_completed_date > 0 AND bp.vc_rw > 1 THEN sf.id_buyer END) AS rec_buyers_with_visits_completed,

        -- Regions with visits
        COUNT(DISTINCT sf.region_code) AS count_region_code_booked,
        COUNT(DISTINCT CASE WHEN sf.sk_visit_completed_date > 0 THEN sf.region_code END) AS count_region_code_visited,

        -- Visit Review Metrics
        COUNT(DISTINCT CASE WHEN sf.agent_performance IS NOT NULL THEN sf.sk_booking  END) AS visits_reviews,
        COUNT(DISTINCT CASE WHEN sf.agent_performance = 5 THEN sf.sk_booking END) AS promoters_reviews,
        COUNT(DISTINCT CASE WHEN sf.agent_performance IN (1, 2, 3) THEN sf.sk_booking END) AS detractors_reviews,
        COUNT(DISTINCT CASE WHEN sf.does_want_same_agent IS FALSE THEN sf.sk_booking END) AS does_not_want_same_agent

    FROM fact_visits AS sf
    LEFT JOIN
        buyer AS bp
            ON bp.sk_booking = sf.sk_booking
    GROUP BY 1, 2
),
avg_8w_vb2oa AS (
    SELECT
        sk_agent,
        week,
        agent_week_order,
        b_oa*1.00/NULLIF(b_vb,0) AS b_vb2oa,
        AVG(b_oa*1.00/NULLIF(b_vb,0)) OVER (PARTITION BY sk_agent ORDER BY week NULLS LAST ROWS BETWEEN 9 PRECEDING AND 2 PRECEDING) AS b_vb2oa_avg8w,
        SUM(b_vb) OVER (PARTITION BY sk_agent ORDER BY week NULLS LAST ROWS BETWEEN 9 PRECEDING AND 2 PRECEDING ) AS sum_b_vb_8w,
        SUM(b_oa) OVER (PARTITION BY sk_agent ORDER BY week NULLS LAST ROWS BETWEEN 9 PRECEDING AND 2 PRECEDING ) AS sum_b_oa_8w,
        SUM(b_os) OVER (PARTITION BY sk_agent ORDER BY week NULLS LAST ROWS BETWEEN 9 PRECEDING AND 2 PRECEDING ) AS sum_b_os_8w
    FROM count_per_agent_week AS cpaw
),
agent_quartil AS (
    SELECT
        avg8w.sk_agent,
        avg8w.week,
        avg8w.sum_b_vb_8w AS buyers_with_bookings_8w,
        avg8w.sum_b_oa_8w AS buyers_with_offers_accepted_8w,
        avg8w.b_vb2oa_avg8w AS buyers_vb2oa_avg8w,
        CAST(ntile(4) OVER (PARTITION BY avg8w.week ORDER BY avg8w.b_vb2oa_avg8w, avg8w.sum_b_oa_8w, avg8w.sum_b_os_8w, avg8w.sum_b_vb_8w) AS BIGINT) AS quinto_8w_moving_avg_quartil,
        CAST(ntile(4) OVER (PARTITION BY avg8w.week, arw.region_code ORDER BY avg8w.b_vb2oa_avg8w, avg8w.sum_b_oa_8w , avg8w.sum_b_os_8w, avg8w.sum_b_vb_8w) AS BIGINT) AS region_8w_moving_avg_quartil
    FROM avg_8w_vb2oa AS avg8w
    LEFT JOIN
        agent_region_week AS arw
            ON arw.week = avg8w.week
            AND avg8w.sk_agent = arw.sk_agent
    WHERE avg8w.agent_week_order > 13
    AND sum_b_vb_8w > 49
)
SELECT
    -- ID
    cpaw.sk_agent,
    cpaw.week,
    CAST(cpaw.agent_week_order AS BIGINT) AS agent_week_order,
    arw.region_code AS region_code,
    wc.contract_name AS work_contract,
    CASE WHEN wc.contract_name LIKE '%HUB%' THEN TRUE ELSE FALSE END AS is_hub_agent,

    -- Event Metrics
    cpaw.bookings,
    cpaw.bookings_by_agent,
    cpaw.visits_ended,
    cpaw.virtual_visits,
    cpaw.visits_completed,
    cpaw.visits_cancelled_agent_reason,
    cpaw.visits_cancelled_by_agent,
    cpaw.no_show_by_agent,
    cpaw.visits_completed*1.00 / NULLIF(cpaw.b_vc,0) AS visits_per_buyer,
    cpaw.offers_submitted,
    cpaw.offers_qualified,
    cpaw.offers_accepted,
    cpaw.sales_agreements,
    cpaw.house_registred,
    cpaw.houses_booked,
    cpaw.houses_visited,

    -- Buyer Metrics
    cpaw.b_vb AS buyers_with_bookings,
    cpaw.b_vc AS buyers_with_visits_completed,
    cpaw.b_os AS buyers_with_offers_submitted,
    cpaw.b_oq AS buyers_with_offers_qualified,
    cpaw.b_oa AS buyers_with_offers_accepted,
    cpaw.b_ccv AS buyers_with_sales_agreements,
    cpaw.b_hr AS buyers_with_house_registred,

    -- New buyers
    cpaw.new_buyers,

    -- Buyer Recurrency
    cpaw.rec_buyers_with_visits_completed,

     -- Quartiles Metrics
    avg8w.sum_b_vb_8w AS buyers_with_bookings_8w,
    avg8w.sum_b_oa_8w AS buyers_with_offers_accepted_8w,
    avg8w.b_vb2oa_avg8w AS buyers_vb2oa_avg8w,
    CASE
        WHEN avg8w.sum_b_vb_8w <= 49 AND avg8w.agent_week_order > 13 THEN 0
        ELSE agq.quinto_8w_moving_avg_quartil
    END AS quinto_8w_moving_avg_quartil,
    CASE
        WHEN avg8w.sum_b_vb_8w <= 49 AND avg8w.agent_week_order > 13 THEN 0
        ELSE agq.region_8w_moving_avg_quartil
    END AS region_8w_moving_avg_quartil,

    -- Regions with visits
    cpaw.count_region_code_booked,
    cpaw.count_region_code_visited,

    -- Weekly Hours
    CAST((wh.weekly_available_hours) AS BIGINT) AS weekly_available_hours,
    CAST((wh.weekly_total_hours) AS BIGINT) AS weekly_total_hours,
    wh.days_w_hours_available,
    wh.weekdays_w_hours_available,

    -- NPS Metrics
    nps.b_nps_answers AS buyers_nps_answers,
    nps.b_promoters AS buyers_promoters,
    nps.b_detractors AS buyers_detractors,
    nps.avg_nps_score,

    -- Visit Review Metrics
    cpaw.visits_reviews,
    promoters_reviews,
    detractors_reviews,
    ((cpaw.promoters_reviews*1.00 - cpaw.detractors_reviews*1.00) / NULLIF(cpaw.visits_reviews*1.00,0))*100 AS nps_visit_review,
    cpaw.does_not_want_same_agent,
    NOW() AS ts_load
FROM
    count_per_agent_week AS cpaw
LEFT JOIN
    buyer_nps AS nps
        ON cpaw.sk_agent = nps.sk_agent
        AND cpaw.week = nps.week
LEFT JOIN
    agent_region_week AS arw
        ON cpaw.sk_agent||cpaw.week = arw.sk_agent||arw.week
LEFT JOIN
    weekly_agent_hours AS wh
        ON cpaw.sk_agent||cpaw.week = wh.sk_agent||wh.week
LEFT JOIN
    avg_8w_vb2oa AS avg8w
        ON avg8w.sk_agent||avg8w.week = cpaw.sk_agent||cpaw.week
LEFT JOIN
    agent_quartil AS agq
        ON agq.sk_agent = cpaw.sk_agent
        AND agq.week = cpaw.week
LEFT JOIN
    datalake_ebdb_clean.work_contract AS wc
        ON wc.id = wh.id_work_contract
WHERE
    cpaw.week IS NOT NULL
ORDER BY 1, 2
