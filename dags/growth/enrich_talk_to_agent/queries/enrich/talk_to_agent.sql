WITH taxonomy_demand AS (
    WITH taxonomy_min_ids AS (
	SELECT
	    MIN(id) AS id
	FROM
	    datalake_gsheets_clean.taxonomy_demand
	WHERE
	    first_update_source = 'Inquilinos'
	    AND CAST(flg_via_reschedule AS STRING) = '0'
	GROUP BY
	    LOWER(app_type),
	    LOWER(utm_source),
	    LOWER(utm_medium),
	    LOWER(branded),
	    LOWER(first_update_source),
	    flg_via_reschedule
)
    SELECT
        CAST(td.id AS BIGINT) AS id,
        td.app_type,
        td.utm_source,
        td.utm_medium,
        td.branded,
        td.Category AS mkt_category,
        td.Flow AS mkt_flow,
        td.Completion AS mkt_completion,
        td.Channel AS mkt_channel,
        td.Medium AS mkt_medium,
        td.Origin AS mkt_origin,
        td.Source AS mkt_source,
        td.Platform AS mkt_platform
    FROM
        datalake_gsheets_clean.taxonomy_demand AS td
    JOIN
        taxonomy_min_ids AS td_min
            ON td.id = td_min.id
),

tta_taxonomy AS (
    WITH tta_raw AS (
        SELECT DISTINCT
	    COALESCE(ep_id_house, -1) AS house,
	    COALESCE(ep_id_agent, -1) AS agent,
	    COALESCE(evt.id_user, -1) AS tenant,
	    up_utm_source AS utm_source,
	    up_utm_medium AS utm_medium,
	    up_utm_campaign AS utm_campaign,
	    up_utm_term AS utm_term,
	    up_utm_content AS utm_content,
	    CASE
	        WHEN (UPPER(up_utm_campaign) LIKE '%BRANDED%'
					     OR UPPER(up_utm_campaign) LIKE '%INSTITUCIONAL%')
				             AND UPPER(up_utm_campaign) NOT LIKE '%NON-BRANDED%'
		    THEN 'Branded'
	    	ELSE 'Outro'
	    END AS branded,
	    platform AS app_type,
	    ts_event AS event_timestamp
        FROM
            datalake_amplitude_clean.170698_piloto_cw_message_sent_events AS evt
    	WHERE
            YEAR > 2020
            OR (YEAR = 2020 AND MONTH >= 3)
    )
    SELECT
        tta.house,
        tta.tenant,
        tta.agent,
        tta.app_type,
        tta.utm_source,
        tta.utm_medium,
        tta.branded,
        td.mkt_category,
        td.mkt_flow,
        td.mkt_completion,
        td.mkt_origin,
    	td.mkt_channel,
    	td.mkt_medium,
    	td.mkt_source,
    	td.mkt_platform,
    	tta.utm_campaign,
    	tta.utm_term,
    	tta.utm_content,
    	tta.event_timestamp,
    	ROW_NUMBER() OVER(
    					PARTITION BY tta.house, tta.tenant, tta.agent
						ORDER BY event_timestamp
						) AS event_order
    FROM
        tta_raw tta
    LEFT JOIN
        taxonomy_demand AS td
            ON LOWER(COALESCE(td.app_type,'')) = LOWER(COALESCE(tta.app_type,''))
            AND LOWER(COALESCE(td.utm_source,'')) = LOWER(COALESCE(tta.utm_source,''))
            AND LOWER(COALESCE(td.utm_medium,'')) = LOWER(COALESCE(tta.utm_medium,''))
            AND LOWER(COALESCE(td.branded,'')) = LOWER(COALESCE(tta.branded,''))
),

-- Completed Talk to Agent accounting FROM Bookings (mainly before 2020/05/20)
bookings_agent_tenant AS (
    SELECT
        CAST(u.id AS INTEGER) AS agent,
        CAST(id_visitor AS INTEGER) AS tenant,
        CAST(id_property AS INTEGER) AS house,
        COUNT(distinct db.sk_booking) AS bookings_by_agent,
        MIN(CAST(db.dt_created AS STRING)) AS first_agent_booking_ts
    FROM
        dw_public.dim_booking AS db
    LEFT JOIN
        dw_public.dim_user u
            ON id_agent=CAST(u.dados_agente_id AS BIGINT)
    WHERE
        db.dt_created > DATE('2020-03-01') --After feature has started
        AND db.first_update_source='AGENT_PWA' --Bookings created by Agents
        AND u.id IS NOT NULL
        AND id_visitor IS NOT NULL
        AND id_property IS NOT NULL
        --considering also "Agendamentos" WHEN the Agent schedule a Visit
        --and date_trunc('day',CAST(db.dt_created as timestamp))=date_trunc('day',CAST(db.dt_scheduling as timestamp)) --Bookings registered BY Agents = they have the same created and scheduling day
    GROUP BY
        1,2,3 -- Only count one attendance for the triple agent-tenant-house
),

-- Filter one version per listing
listing AS (
    SELECT
        CAST(id_house AS BIGINT) AS id_house,
        CAST(MAX(sk_house_listing) AS BIGINT) AS sk_house_listing
    FROM
        dw_rent.dim_house_listing
    WHERE
        CAST(sk_house_listing AS STRING) > ''
        AND CAST(id_house AS STRING) > ''
    GROUP BY
        1
),

-- Completed Talk to Agent accounting FROM AgentSupport (mainly after 2020/05/20)
registered_tta AS (
    SELECT
        CAST(u.id AS INTEGER) AS agent,
        CAST(a.id_user AS INTEGER) AS tenant,
        CAST(h.id_house AS INTEGER) AS house,
        COUNT(*) AS attendances_by_agent,
        substr(CAST(MIN(a.ts_created) AS STRING),1,19) AS first_agent_attendance_ts
    FROM
        datalake_ebdb_clean.agent_support AS a --this one is not on clean yet
    JOIN
        datalake_ebdb_clean.listing_business_context AS bc
            ON bc.id = a.id_listing
    JOIN
        dw_rent.dim_house_listing AS h
            ON bc.id_house = CAST(h.id_house AS BIGINT)
    JOIN
        dw_public.dim_user AS u
            ON CAST(u.dados_agente_id AS BIGINT) = a.id_agent
    JOIN
        listing AS l
            ON CAST(h.sk_house_listing AS BIGINT) = CAST(l.sk_house_listing AS BIGINT)
    WHERE
        CAST(h.id_house AS STRING) > ''
        AND u.dados_agente_id IS NOT NULL
        AND a.status = 'COMPLETE' --here at this stage of Prod. Dev. we want to account only for Completed Talk to Agents
    GROUP BY
        1,2,3 -- Only count one attendance for the triple agent-tenant-house
),


-- Completed Talk to Agent (everything)
talk_to_agent_completed AS (
    SELECT
        COALESCE(b.agent,t.agent) AS agent,
        COALESCE(b.tenant,t.tenant) AS tenant,
        COALESCE(b.house,t.house) AS house,
        MAX(b.bookings_by_agent) AS bookings_by_agent,
        MAX(t.attendances_by_agent) AS attendances_by_agent,
        MIN(COALESCE(b.first_agent_booking_ts,t.first_agent_attendance_ts)) AS first_attendance_ts,
        MIN(b.first_agent_booking_ts) AS first_agent_booking_ts,
        MIN(t.first_agent_attendance_ts) AS first_agent_attendance_ts
    FROM
        bookings_agent_tenant AS b
    FULL OUTER JOIN
        registered_tta AS t
            ON b.agent=t.agent
            AND b.tenant=t.tenant
            AND b.house=t.house
    GROUP BY
        1,2,3
),

--Listing region code
house_properties AS(
    SELECT
        h.id AS sk_house_listing,
        r.region_code
    FROM
        datalake_ebdb_clean.house AS h
    LEFT JOIN
        dw_public.dim_region AS r
            ON CAST(r.id AS BIGINT)=h.id_region
),

-- Events (current registry for every Talk to Agent started)
events AS(
    SELECT
        ep_id_house AS house_id,
        ep_id_agent AS agent_id,
        id_user AS tenant_id,
        MIN(NULLIF(substr(CAST(ts_event AS STRING),1,19),'')) AS first_message_ts,
        ARRAY_JOIN(COLLECT_LIST(REPLACE(TRIM(SUBSTR(REGEXP_EXTRACT(REPLACE(REGEXP_REPLACE(ep_message_content,'\n',' '),'''',' '),'(?<=(([0-9]{{9}}))).*', 0),3)), 'omprar.', '')), '+') AS message,
        COUNT(*) AS count_messages
    FROM
        datalake_amplitude_clean.170698_piloto_cw_message_sent_events AS evt
    WHERE
        YEAR > 2020
        OR (YEAR = 2020 AND MONTH >= 3)
    GROUP BY
        1,2,3
),

--putting everything together
final AS(
    SELECT
        e.agent_id,
        e.tenant_id,
        e.house_id,
        m.sk_house_listing,
        CASE
            WHEN t.first_attendance_ts IS NULL
                THEN false
            ELSE true
        END AS attended,
        e.message,
        u.nome AS tenant_name,
        u.telefone_principal AS tenant_phone,
        u.email AS tenant_email,
        count_messages AS msg_sent,
        CASE
            WHEN t.first_attendance_ts IS NULL
                THEN 1.00*FLOOR((unix_timestamp(current_timestamp - interval 3 hours) - unix_timestamp(CAST(e.first_message_ts AS TIMESTAMP))) / 60)/60
        END AS delta_hours_elapsed,
        CASE
            WHEN t.first_attendance_ts IS NOT NULL
                THEN 1.00*FLOOR((unix_timestamp(CAST(t.first_attendance_ts AS TIMESTAMP)) - unix_timestamp(CAST(e.first_message_ts AS TIMESTAMP))) / 60)/60
            ELSE NULL
        END AS delta_hours_attended,
        h.region_code,
        CASE
            WHEN sa.id IS NULL
                THEN 'RENT'
            ELSE 'SALE'
        END AS business_context,
        e.first_message_ts,
        t.bookings_by_agent,
        t.attendances_by_agent,
        t.first_attendance_ts,
        COALESCE(mkt.app_type, '') AS app_type,
        COALESCE(mkt.utm_source, '') AS utm_source,
        COALESCE(mkt.utm_medium, '') AS utm_medium,
        COALESCE(mkt.branded, '') AS branded,
        COALESCE(mkt.mkt_category, 'Not Mapped') AS mkt_category,
        COALESCE(mkt.mkt_flow, 'Not Mapped') AS mkt_flow,
        COALESCE(mkt.mkt_completion, 'Not Mapped') AS mkt_completion,
        COALESCE(mkt.mkt_origin, 'Not Mapped') AS mkt_origin,
        COALESCE(mkt.mkt_channel, 'Not Mapped') AS mkt_channel,
        COALESCE(mkt.mkt_medium, 'Not Mapped') AS mkt_medium,
        COALESCE(mkt.mkt_source, 'Not Mapped') AS mkt_source,
        COALESCE(mkt.mkt_platform, 'Not Mapped') AS mkt_platform,
        COALESCE(mkt.utm_campaign, '') AS utm_campaign,
        COALESCE(mkt.utm_term, '') AS utm_term,
        COALESCE(mkt.utm_content, '') AS utm_content
    FROM
        events AS e
    LEFT JOIN
        talk_to_agent_completed AS t
            ON t.tenant=e.tenant_id
            AND t.agent=e.agent_id
            AND t.house=e.house_id
    LEFT JOIN
        dw_public.dim_user AS u
            ON u.id=e.tenant_id
    LEFT JOIN
        house_properties AS h
            ON CAST(h.sk_house_listing AS INTEGER) = e.house_id
    -- identifies the agent context with the booleans columns in user dimension: is_sale_agent
    LEFT JOIN
        dw_public.dim_user AS sa
            ON CAST(e.agent_id AS INTEGER) = CAST(sa.id AS INTEGER)
            AND sa.is_sale_agent
    -- version of the moment the tenant has sent the message
    JOIN
        dw_rent.dim_house_listing AS m
            ON e.house_id = CAST(NULLIF(CAST(m.id_house AS STRING),'') AS BIGINT)
            AND CAST(ts_listing_version_start AS STRING) <  e.first_message_ts
            AND (CAST(ts_listing_version_end AS STRING)='' OR CAST(ts_listing_version_end AS STRING) > e.first_message_ts)
    -- marketing taxonomy
    JOIN
        tta_taxonomy AS mkt
            ON mkt.tenant = COALESCE(e.tenant_id, -1)
            AND mkt.agent = COALESCE(e.agent_id, -1)
            AND mkt.house = COALESCE(e.house_id, -1)
            AND event_order = 1
    )

-- validator
--SELECT count(*) as total_tta, count(CASE WHEN attended=true THEN 1 end) as total_attended, count(CASE WHEN bookings_by_agent>0 THEN 1 end) as bookings_by_agent,count(CASE WHEN attendances_by_agent>0 THEN 1 end) as attendances_by_agent  FROM final
SELECT
    CAST(agent_id AS STRING) AS agent_id,
    CAST(tenant_id AS STRING) AS tenant_id,
    CAST(house_id AS STRING) AS house_id,
    CAST(sk_house_listing AS STRING) AS sk_house_listing,
    CAST(attended AS STRING) AS attended,
    CAST(message AS STRING) AS message,
    CAST(tenant_name AS STRING) AS tenant_name,
    CAST(tenant_phone AS STRING) AS tenant_phone,
    CAST(tenant_email AS STRING) AS tenant_email,
    CAST(msg_sent AS STRING) AS msg_sent,
    CAST(delta_hours_elapsed AS STRING) AS delta_hours_elapsed,
    CAST(delta_hours_attended AS STRING) AS delta_hours_attended,
    CAST(region_code AS STRING) AS region_code,
    CAST(business_context AS STRING) AS business_context,
    CAST(first_message_ts AS STRING) AS first_message_ts,
    CAST(bookings_by_agent AS STRING) AS bookings_by_agent,
    CAST(attendances_by_agent AS STRING) AS attendances_by_agent,
    CAST(first_attendance_ts AS STRING) AS first_attendance_ts,
    NULLIF(CAST(app_type AS STRING), "") AS app_type,
    NULLIF(CAST(utm_source AS STRING), "") AS utm_source,
    NULLIF(CAST(utm_medium AS STRING), "") AS utm_medium,
    CAST(branded AS STRING) AS branded,
    CAST(mkt_category AS STRING) AS mkt_category,
    CAST(mkt_flow AS STRING) AS mkt_flow,
    CAST(mkt_completion AS STRING) AS mkt_completion,
    CAST(mkt_origin AS STRING) AS mkt_origin,
    CAST(mkt_channel AS STRING) AS mkt_channel,
    CAST(mkt_medium AS STRING) AS mkt_medium,
    CAST(mkt_source AS STRING) AS mkt_source,
    CAST(mkt_platform AS STRING) AS mkt_platform,
    NULLIF(CAST(utm_campaign AS STRING), "") AS utm_campaign,
    NULLIF(CAST(utm_term AS STRING), "") AS utm_term,
    NULLIF(CAST(utm_content AS STRING), "") AS utm_content,
    CAST(NOW() AS STRING) AS ts_load
FROM
    final
