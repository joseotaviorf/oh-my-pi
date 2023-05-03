WITH removed_company_status_oscillations AS (
    SELECT
        cs.id_company,
        cs.id_user_updated_by,
        cs.source_type,
        CASE
            WHEN cs.lead_status = 'Lead' THEN 'Lead'
            WHEN cs.lead_status = 'Prospect' THEN 'Prospect'
            WHEN cs.lead_status IN ('Pré Contatado', 'Contatado', 'Pré qualificado') THEN 'Pre Qualified'
            WHEN cs.lead_status = 'Qualificado' THEN 'Qualified'
            WHEN cs.lead_status = 'Oportunidade' THEN 'Opportunity'
            WHEN cs.lead_status IN ('Parceiro', 'Membro') THEN 'Membership Started'
            WHEN cs.lead_status IN ('Inativo', 'Perdido', 'Desclassificação comercial') THEN 'Membership Ended'
            WHEN cs.lead_status = 'Churn Tombamento' THEN 'Churn'
            WHEN cs.lead_status = 'Em processo tombamento' THEN 'Contract Transition Started'
        END AS event,
        cs.lead_status AS hubspot_event_detail,
        'Status' AS hubspot_event_origin,
        cs.lead_status IN ('Inativo', 'Perdido', 'Desclassificação comercial') AS is_loss,
        LAG(lead_status) OVER (PARTITION BY id_company ORDER BY ts_status_started) AS previous_status,
        LEAD(lead_status) OVER (PARTITION BY id_company ORDER BY ts_status_started) AS next_status,
        LEAD(ts_status_started) OVER (PARTITION BY id_company ORDER BY ts_status_started) AS ts_next_status_started,
        cs.ts_status_started AS ts_event
    FROM
        datalake_hubspot.company_status AS cs
    QUALIFY
        event IS NOT NULL -- Ignore events that were not treated
        AND (next_status IS NULL -- Ignore events that go back and forth to the same status within the same 24h
        OR UNIX_TIMESTAMP(ts_next_status_started) - UNIX_TIMESTAMP(ts_event) > 60 * 60 * 24
        OR next_status IS DISTINCT FROM previous_status)
),
deal_stage_renamed AS (
    SELECT
        d.id_company,
        d.id_deal,
        ds.id_user_updated_by,
        ds.source_type,
        CASE TRIM(s.id_stage)
            WHEN 16603552 THEN 'Growth Mkt Nutrition' -- Nutrição Growth Mkt (NG)
            WHEN 69265218 THEN 'Prioritized' -- Imobiliárias Priorizadas (IP)
            WHEN 69242389 THEN 'Contact Attempt' -- Tentativa de Contato (TC)
            WHEN 69272715 THEN 'Successful Contact' -- Contato Realizado (CR)
            WHEN 36160399 THEN 'Negotiation Meeting Pending' -- Pendente Reunião - Inside Sales
            WHEN 52253368 THEN 'Negotiation Meeting Pending' -- Negociação Pendente - Field Sales
            WHEN 29546857 THEN 'Negotiation Meeting Scheduled' -- Reunião Agendada (RA)
            WHEN 31313774 THEN 'Negotiation Meeting Completed' -- Reunião Realizada
            WHEN 36160400 THEN 'Negotiation In Progress' -- Negociação em Andamento
            WHEN 36247092 THEN 'Negotiation In Progress' -- Negociação - Inside Sales
            WHEN 26378054 THEN 'Deal Won' -- Negócio Ganho
            WHEN 69301115 THEN 'Deal Won' -- Negócio Fechado (NF)
            WHEN 16603553 THEN 'Awaiting Documents' -- Aguardando Documentos (AD)
            WHEN 26410914 THEN 'Documents Received' -- Documentos Recebidos (DR)
            WHEN 26410915 THEN 'Term Sent' -- Termo Enviado (TE)
            WHEN 16603554 THEN 'Membership Started' -- Termo Assinado (TA)
            WHEN 39565081 THEN 'Churn Risk' -- Risco de Churn
            WHEN 50084225 THEN 'Contract Termination Analysis' -- Análise de Distrato
            WHEN 16603555 THEN 'Deal Lost' -- Negócio Perdido (NP)
            WHEN 37137462 THEN 'Churn' -- Churn
        END AS event,
        s.label AS hubspot_event_detail,
        'Deal' AS hubspot_event_origin,
        s.id_stage = 16603555 AS is_loss, -- Negócio Perdido (NP)
        s.id_stage IN ( -- We need to know this in order to identify when something goes from Deal Won to a previous stage
            26378054, -- Negócio Ganho
            69301115, -- Negócio Fechado (NF)
            16603553, -- Aguardando Documentos (AD)
            26410914, -- Documentos Recebidos (DR)
            26410915, -- Termo Enviado (TE)
            16603554, -- Termo Assinado (TA)
            39565081, -- Risco de Churn
            50084225 -- Análise de Distrato
        ) AS is_after_deal_won,
        ds.ts_stage_started AS ts_event
    FROM
        datalake_hubspot.deal_stage AS ds
    JOIN
        datalake_hubspot.deal AS d
            ON ds.id_deal = d.id_deal
    JOIN
        datalake_hubspot.stage AS s
            ON s.id_stage = ds.id_stage
    JOIN
        datalake_hubspot.pipeline AS p
            ON p.id_pipeline = ds.id_pipeline
    WHERE
        p.id_pipeline = 5160960
    QUALIFY 
        LAST(event, TRUE) OVER (PARTITION BY id_company ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) IS DISTINCT FROM event
        AND event IS NOT NULL
),
removed_deal_stage_oscillations AS (
    SELECT *,
        LAG(event) OVER (PARTITION BY id_company ORDER BY ts_event) AS previous_status,
        LEAD(event) OVER (PARTITION BY id_company ORDER BY ts_event) AS next_status,
        LEAD(ts_event) OVER (PARTITION BY id_company ORDER BY ts_event) AS ts_next_status_started
    FROM
        deal_stage_renamed
    QUALIFY  -- Ignore events that go back and forth to the same status within the same 24h
        UNIX_TIMESTAMP(ts_next_status_started) - UNIX_TIMESTAMP(ts_event) > 60 * 60 * 24
        OR next_status IS NULL
        OR next_status IS DISTINCT FROM previous_status
),
removed_ticket_stage_oscillations AS (
    SELECT
        d.id_company,
        CASE
            WHEN s.id_pipeline IN (5137154, 9317192, 9317747) THEN ts.id_ticket
        END AS id_ticket_demand_onboarding,
        CASE
            WHEN s.id_pipeline = 7784309 THEN ts.id_ticket
        END AS id_ticket_supply_onboarding,
        ts.id_user_updated_by,
        ts.source_type,
        CASE
            WHEN s.id_stage IN (27195509, 26557112) THEN 'Welcome Email' -- E-mail de Boas Vindas Enviado
            WHEN s.id_stage = 22048412 THEN 'Supply Onboarding Meeting Pending' -- Pendente Reunião
            WHEN s.id_stage = 24339603 THEN 'Supply Onboarding Scheduled' -- Reunião Agendada
            WHEN s.id_stage = 38678440 THEN 'Supply Onboarding Meeting Completed' -- Reunião Realizada
            WHEN s.id_stage = 24339605 THEN 'CRM Settings' -- Configuração CRM
            WHEN s.id_stage = 38678441 THEN 'Dedup Received' -- Recebimento Dedup
            WHEN s.id_stage = 22677053 THEN 'Listings Validated' -- Validação da Listagem
            WHEN s.id_stage = 22677054 THEN 'First Lead 3P' -- Leads Enviados para a Rede
            WHEN s.id_stage = 25122068 THEN 'First Listing' -- Imóveis Publicados
            WHEN s.id_stage IN (16620599, 26653758) THEN 'Demand Onboarding Scheduled' -- Onboarding Agendado
            WHEN s.id_stage IN (16620600, 26647645) THEN 'Demand Onboarding Completed' -- Onboarding Realizado
            -- Corretor finalizou onboarding, Agendou primeira visita
            WHEN s.id_stage IN (29531712, 26557189) THEN 'Demand Onboarding Completed'
            WHEN s.id_stage = 27834401 THEN 'Contract Transition Completed' -- Assinado
            WHEN s.id_stage IN (20894770, 26557190, 26647646) THEN 'Demand Onboarding Given Up' -- Desistência
            WHEN s.id_stage = 22677055 THEN 'Supply Onboarding Given Up' -- Desistência
        END AS event,
        s.label AS hubspot_event_detail,
        tp.label AS hubspot_event_origin,
        FALSE AS is_loss,
        CASE
            WHEN s.id_pipeline IN (5137154, 9317192, 9317747) THEN 'Demand Onboarding'
            WHEN s.id_pipeline = 7784309 THEN 'Supply Onboarding'
            WHEN s.id_pipeline = 9505972 THEN 'Contract Transition'
            ELSE 'Unknown'
        END AS event_type,
        LAG(s.label) OVER (PARTITION BY d.id_company, tp.id_pipeline ORDER BY ts.ts_stage_started) AS previous_status,
        LEAD(s.label) OVER (PARTITION BY d.id_company, tp.id_pipeline ORDER BY ts.ts_stage_started) AS next_status,
        LEAD(ts.ts_stage_started) OVER (PARTITION BY d.id_company, tp.id_pipeline ORDER BY ts.ts_stage_started) AS ts_next_status_started,
        ts.ts_stage_started AS ts_event
    FROM
        datalake_hubspot.ticket_stage AS ts
    JOIN
        datalake_hubspot.stage AS s
            ON ts.id_stage = s.id_stage
    JOIN
        datalake_hubspot.ticket AS t
            ON t.id_ticket = ts.id_ticket
    JOIN
        datalake_hubspot.deal AS d
            ON d.id_deal = t.id_deal
    JOIN
        datalake_hubspot.pipeline AS tp
            ON tp.id_pipeline = ts.id_pipeline
    JOIN
        datalake_hubspot.pipeline AS dp
            ON dp.id_pipeline = d.id_pipeline
    WHERE
        dp.id_pipeline = 5160960
    QUALIFY 
        event IS NOT NULL -- Ignore events that were not treated
        AND (next_status IS NULL -- Ignore events that go back and forth to the same status within the same 24h
        OR UNIX_TIMESTAMP(ts_next_status_started) - UNIX_TIMESTAMP(ts_event) > 60 * 60 * 24
        OR next_status IS DISTINCT FROM previous_status)
),
status_changes AS (
    SELECT
        id_company,
        NULL::BIGINT AS id_deal,
        NULL::BIGINT AS id_ticket_demand_onboarding,
        NULL::BIGINT AS id_ticket_supply_onboarding,
        id_user_updated_by,
        source_type,
        event,
        hubspot_event_detail,
        hubspot_event_origin,
        'Status' AS event_type,
        is_loss,
        NULL::BOOLEAN AS is_after_deal_won,
        ts_event
    FROM
        removed_company_status_oscillations
    QUALIFY
        LAG(event) OVER (PARTITION BY id_company ORDER BY ts_event) IS DISTINCT FROM event
    UNION ALL
    SELECT
        id_company,
        NULL::BIGINT AS id_deal,
        NULL::BIGINT AS id_ticket_demand_onboarding,
        NULL::BIGINT AS id_ticket_supply_onboarding,
        NULL::BIGINT AS id_user_updated_by,
        'Archivation' AS source_type,
        'Membership Ended' AS event,
        NULL AS hubspot_event_detail,
        NULL AS hubspot_event_origin,
        'Status' AS event_type,
        TRUE AS is_loss,
        NULL::BOOLEAN AS is_after_deal_won,
        ts_archived AS ts_event
    FROM
        datalake_hubspot.company
    WHERE
        is_archived -- Artificially add membership end for archived companies. If it is not a member, the event will be renamed to 'Deal Lost' later.
    UNION ALL
    SELECT
        id_company,
        id_deal,
        NULL::BIGINT AS id_ticket_demand_onboarding,
        NULL::BIGINT AS id_ticket_supply_onboarding,
        id_user_updated_by,
        source_type,
        event,
        hubspot_event_detail,
        hubspot_event_origin,
        'Deal' AS event_type,
        is_loss,
        is_after_deal_won,
        ts_event
    FROM
        removed_deal_stage_oscillations
    QUALIFY
        LAG(event) OVER (PARTITION BY id_company ORDER BY ts_event) IS DISTINCT FROM event
    UNION ALL
    SELECT
        id_company,
        NULL AS id_deal,
        id_ticket_demand_onboarding,
        id_ticket_supply_onboarding,
        id_user_updated_by,
        source_type,
        event,
        hubspot_event_detail,
        hubspot_event_origin,
        event_type,
        is_loss,
        NULL::BOOLEAN AS is_after_deal_won,
        ts_event
    FROM
        removed_ticket_stage_oscillations
    QUALIFY
        LAG(event) OVER (PARTITION BY id_company ORDER BY ts_event) IS DISTINCT FROM event
    UNION ALL
    SELECT
        id_company_demand AS id_company,
        NULL AS id_deal,
        NULL AS id_ticket_demand_onboarding,
        NULL AS id_ticket_supply_onboarding,
        NULL AS id_user_updated_by,
        'Main' AS source_type,
        'First Demand Visit Booked' AS event,
        NULL AS hubspot_event_detail,
        NULL AS hubspot_event_origin,
        'Demand Onboarding' AS event_type,
        NULL AS is_loss,
        NULL::BOOLEAN AS is_after_deal_won,
        ts_created AS ts_event
    FROM
        datalake_booking.booking
    WHERE
        id_company_demand IS NOT NULL
    UNION ALL
    SELECT
        h.id_company_hubspot AS id_company,
        NULL AS id_deal,
        NULL AS id_ticket_demand_onboarding,
        NULL AS id_ticket_supply_onboarding,
        NULL AS id_user_updated_by,
        'Main' AS source_type,
        'First Listing' AS event,
        NULL AS hubspot_event_detail,
        NULL AS hubspot_event_origin,
        'Supply Onboarding' AS event_type,
        NULL AS is_loss,
        NULL::BOOLEAN AS is_after_deal_won,
        ts_first_publication AS ts_event
    FROM
        datalake_sale_listings.sale_listing AS sl
    JOIN
        datalake_ebdb_listing.house AS h
            ON h.id = sl.id_house
    WHERE
        h.id_company_hubspot IS NOT NULL
        AND ts_first_publication IS NOT NULL
    UNION ALL
    SELECT
        id_company_hubspot AS id_company,
        NULL AS id_deal,
        NULL AS id_ticket_demand_onboarding,
        NULL AS id_ticket_supply_onboarding,
        NULL AS id_user_updated_by,
        'Supply Processor' AS source_type,
        'First Lead 3P' AS event,
        NULL AS hubspot_event_detail,
        NULL AS hubspot_event_origin,
        'Supply Onboarding' AS event_type,
        NULL AS is_loss,
        NULL::BOOLEAN AS is_after_deal_won,
        ts_created AS ts_event
    FROM
        datalake_brokers_supply_processor.lead_3p
    WHERE 
        id_company_hubspot IS NOT NULL
),
merged_with_last_status AS (
    SELECT
        sc.*,
        LAST(
            CASE
                WHEN sc.event_type = 'Status' THEN sc.event
            END, TRUE
        ) OVER(
            PARTITION BY
                sc.id_company
            ORDER BY
                sc.ts_event
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS last_status,
        LAST(
            CASE
                WHEN sc.event_type = 'Deal' THEN sc.event
            END, TRUE
        ) OVER(
            PARTITION BY
                sc.id_company
            ORDER BY
                sc.ts_event
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS last_deal_stage
    FROM
        status_changes AS sc
    JOIN
        datalake_hubspot.company AS c
            ON sc.id_company = c.id_company
    WHERE
        NOT c.is_merged_into_other_company -- Remove companies that were merged into others, since their journey is already represented there
),
treated AS (
    SELECT
        COALESCE(LAST(
            CASE
                WHEN event = 'Membership Started' THEN TRUE -- Last event was membership started
                WHEN event IN ('Membership Ended') THEN FALSE -- Last event was membership ended
                WHEN event_type = 'Status' -- Status went back
                    AND event NOT IN ('Membership Started', 'Contract Transition Started') THEN FALSE
                WHEN event_type = 'Deal' -- Deal stage went back
                    AND event NOT IN ('Contract Termination Analysis', 'Churn Risk')
                    AND last_status NOT IN ('Membership Started', 'Contract Transition Started') THEN FALSE
            END, TRUE
        ) OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_event
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), FALSE) AS was_member_before_event,
        COALESCE(LAST(
            CASE
                WHEN event = 'Membership Started' THEN TRUE
                WHEN event IN ('Membership Ended', 'Deal Lost') THEN FALSE 
                WHEN event_type = 'Status' -- Status went back after being a member, deal was lost
                    AND last_status IN ('Membership Started', 'Contract Transition Started')
                    AND event NOT IN ('Membership Started', 'Contract Transition Started') THEN FALSE
                WHEN event_type = 'Deal' THEN is_after_deal_won
            END, TRUE
        ) OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_event
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), FALSE) AS was_deal_won_before_event,
        COALESCE(LAST(
            CASE
                WHEN event_type = 'Status' THEN event = 'Contract Transition Started'
            END, TRUE
        ) OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_event
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), FALSE) AS was_in_contract_transition_before_event,
        *
    FROM
        merged_with_last_status
    WHERE
        -- Ignore cases when it is still a member, but marked as deal lost
        event != 'Deal Lost'
        OR last_status NOT IN ('Membership Started', 'Contract Transition Started')
    QUALIFY
        event_type IN ('Deal', 'Status', 'Contract Transition')
        OR was_member_before_event -- We only show ticket, lead 3p, listing or booking events if the company was already a member at that journey
),
treated_with_loss AS (
    SELECT *,
        COALESCE(CASE
            WHEN is_loss AND last_status IN ('Membership Started', 'Contract Transition Started') AND event_type = 'Deal' THEN FALSE
            ELSE is_loss
        END, FALSE) AS is_current_loss,
        LAST(
            CASE
                WHEN is_loss AND last_status IN ('Membership Started', 'Contract Transition Started') AND event_type = 'Deal' THEN FALSE
                ELSE is_loss
            END, TRUE
        ) OVER (PARTITION BY id_company ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS is_previous_loss
    FROM
        treated
),
-- The main goal of this CTE is to identify the journey number
-- We start a new journey right after the membership ends, or the deal is lost
treated_with_journey_number AS (
    SELECT
        id_company,
        LAST(id_deal, TRUE) OVER (PARTITION BY id_company ORDER BY ts_event) AS id_deal,
        LAST(id_ticket_demand_onboarding, TRUE) OVER (PARTITION BY id_company ORDER BY ts_event) AS id_ticket_demand_onboarding,
        LAST(id_ticket_supply_onboarding, TRUE) OVER (PARTITION BY id_company ORDER BY ts_event) AS id_ticket_supply_onboarding,
        id_user_updated_by,
        source_type,
        CASE
            WHEN event = 'Membership Started' -- If it was a member in contract transition, and it comes back to member, the contract transition was completed
                AND was_member_before_event
                AND was_in_contract_transition_before_event
                    THEN 'Contract Transition Completed'
            WHEN event = 'Membership Ended' -- If the event was a membership end, but it was not a member in the first place, the correct name would be Deal Lost
                AND NOT was_member_before_event
                    THEN 'Deal Lost'
            WHEN last_status NOT IN ('Membership Started', 'Contract Transition Started') AND event = 'Deal Lost' -- If it was a member only due to term signed (status not updated), but a Deal Lost happened, the correct name is Membership Ended
                AND was_member_before_event
                    THEN 'Membership Ended'
            ELSE event
        END AS event,
        event_type,
        hubspot_event_detail,
        hubspot_event_origin,
        COUNT(
            CASE
                WHEN (
                        is_previous_loss 
                        AND NOT is_current_loss
                    ) -- Previous event was a loss (end of journey), and the current event starts a new journey (is not a loss)
                    OR ( -- Was member but status changed to something else
                        NOT is_current_loss
                        AND was_member_before_event 
                        AND (
                            (event_type = 'Status' AND event NOT IN ('Membership Started', 'Contract Transition Started'))
                            OR (
                                event_type = 'Deal'
                                AND event NOT IN ('Contract Termination Analysis', 'Churn Risk')
                                AND last_status NOT IN ('Membership Started', 'Contract Transition Started')
                            )
                        )
                    )
                    OR ( -- Was not a member, but deal stage was won and went back to something else
                        NOT is_current_loss
                        AND NOT was_member_before_event
                        AND was_deal_won_before_event
                        AND NOT is_after_deal_won
                    )
                        THEN 1
            END
        ) OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_event
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS journey_number, -- Counts every time a new journey begins, which is marked by the previous status being a loss, but not the current one
        was_member_before_event,
        ts_event
    FROM
        treated_with_loss
    WHERE
        NOT (is_previous_loss AND is_current_loss) -- No need for two concurrent losses of a journey
),
complete_journeys AS (
    SELECT
        twjn.id_company,
        twjn.journey_number AS id_journey,
        twjn.id_deal,
        twjn.id_ticket_demand_onboarding,
        twjn.id_ticket_supply_onboarding,
        twjn.id_user_updated_by,
        COALESCE(twjn.source_type, 'Unknown') AS source_type,
        twjn.event,
        twjn.event_type,
        COALESCE(twjn.hubspot_event_detail, 'N/A') AS hubspot_event_detail,
        COALESCE(twjn.hubspot_event_origin, 'N/A') AS hubspot_event_origin,
        COALESCE(cs.lead_status, 'N/A') AS hubspot_company_status,
        COALESCE(s_deal.label, 'N/A') AS hubspot_deal_stage,
        COALESCE(s_demand.label, 'N/A') AS hubspot_demand_onboarding_ticket_stage,
        COALESCE(s_supply.label, 'N/A') AS hubspot_supply_onboarding_ticket_stage,
        was_member_before_event,
        twjn.ts_event
    FROM
        treated_with_journey_number AS twjn
    LEFT JOIN
        datalake_hubspot.company_status AS cs
            ON cs.id_company = twjn.id_company
            AND twjn.ts_event >= cs.ts_status_started AND twjn.ts_event < COALESCE(cs.ts_status_ended, NOW())
    LEFT JOIN
        datalake_hubspot.deal_stage AS ds
            ON ds.id_deal = twjn.id_deal
            AND twjn.ts_event >= ds.ts_stage_started AND twjn.ts_event < COALESCE(ds.ts_stage_ended, NOW())
    LEFT JOIN
        datalake_hubspot.stage AS s_deal
            ON ds.id_stage = s_deal.id_stage 
    LEFT JOIN
        datalake_hubspot.ticket_stage AS ts_demand
            ON ts_demand.id_ticket = twjn.id_ticket_demand_onboarding
            AND twjn.ts_event >= ts_demand.ts_stage_started AND twjn.ts_event < COALESCE(ts_demand.ts_stage_ended, NOW())
    LEFT JOIN
        datalake_hubspot.stage AS s_demand
            ON ts_demand.id_stage = s_demand.id_stage
    LEFT JOIN
        datalake_hubspot.ticket_stage AS ts_supply
            ON ts_supply.id_ticket = twjn.id_ticket_supply_onboarding
            AND twjn.ts_event >= ts_supply.ts_stage_started AND twjn.ts_event < COALESCE(ts_supply.ts_stage_ended, NOW())
    LEFT JOIN
        datalake_hubspot.stage AS s_supply
            ON ts_supply.id_stage = s_supply.id_stage 
    WHERE
        twjn.id_company IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY twjn.id_company, twjn.event, twjn.journey_number ORDER BY ts_event) = 1
)
SELECT *
FROM
    complete_journeys
UNION ALL
--  When the journey ends due to a status change, we artificially insert a membership ended or deal lost row 1ms before
SELECT
    id_company,
    LAG(cj.id_journey) OVER (PARTITION BY id_company ORDER BY ts_event) AS id_journey,
    id_deal,
    id_ticket_demand_onboarding,
    id_ticket_supply_onboarding,
    id_user_updated_by,
    source_type,
    CASE
        WHEN was_member_before_event THEN 'Membership Ended'
        ELSE 'Deal Lost'
    END AS event,
    event_type,
    hubspot_event_detail,
    hubspot_event_origin,
    hubspot_company_status,
    hubspot_deal_stage,
    hubspot_demand_onboarding_ticket_stage,
    hubspot_supply_onboarding_ticket_stage,
    was_member_before_event,
    ts_event - INTERVAL 0.001 SECOND AS ts_event
FROM
    complete_journeys AS cj
QUALIFY
    LAG(cj.id_journey) OVER (PARTITION BY id_company ORDER BY ts_event) < cj.id_journey
    AND LAG(cj.event) OVER (PARTITION BY id_company ORDER BY ts_event) NOT IN ('Membership Ended', 'Deal Lost')