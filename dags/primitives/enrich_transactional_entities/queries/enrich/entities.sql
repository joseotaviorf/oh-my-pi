WITH visit AS (
    WITH visit_base AS (
        SELECT
            id_visit AS id_entity,
            id_house,
            CAST(NULL AS BIGINT) AS id_contract,
            id_owner,
            id_visitor,
            id_agent,
            'VISIT' AS entity,
            business_context,
            TO_JSON(
                STRUCT(
                    computed_status AS computed_status,
                    ts_visit AS ts_visit
                )
            ) AS properties,
            CASE
                WHEN computed_status IN ('CANCELED', 'DONE', 'REQUEST_CANCELED', 'UNSUCCESSFUL', 'STALLED') THEN FALSE
                WHEN computed_status IN ('CONFIRMED', 'REQUESTED') THEN TRUE
                ELSE NULL
            END AS is_active,
            ts_created,
            ts_updated
        FROM
            core_visit.visit
        WHERE
            YEAR(ts_visit) >= 2025
    )
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_owner AS id_user,
        entity,
        'OWNER' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit_base
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_visitor AS id_user,
        entity,
        CASE
            WHEN business_context = 'RENT' THEN 'TENANT_PROSPECT'
            WHEN business_context = 'SALE' THEN 'BUYER_PROSPECT'
        END AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit_base
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_agent AS id_user,
        entity,
        'AGENT_BROKER' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit_base
    WHERE
        id_agent IS NOT NULL
),
offer AS (
    WITH offer_base AS (
        SELECT
            id_offer AS id_entity,
            id_house,
            CAST(NULL AS BIGINT) AS id_contract,
            id_tenant,
            id_owner,
            'FR_OFFER' AS entity,
            'RENT' AS business_context,
            TO_JSON(
                STRUCT(
                    status AS status,
                    ts_expiration AS when
                )
            ) AS properties,
            CASE
                WHEN status = 'PROPOSED' THEN TRUE
                WHEN status IN ('ACCEPTED', 'DISMISSED', 'REJECTED') THEN FALSE
                ELSE NULL
            END AS is_active,
            ts_created,
            ts_updated
        FROM
            core_offer.offer
    )
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_tenant AS id_user,
        entity,
        'TENANT_PROSPECT' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        offer_base
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_owner AS id_user,
        entity,
        'OWNER' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        offer_base
),
contract AS (
    WITH contract_base AS (
        SELECT
            id_contract AS id_entity,
            id_house,
            id_contract,
            id_owner,
            id_tenant,
            'FR_CONTRACT' AS entity,
            'RENT' AS business_context,
            TO_JSON(
                STRUCT(
                    status AS status,
                    dt_started AS when
                )
            ) AS properties,
            CASE
                WHEN status IN ('Cancelado', 'Finalizado') THEN FALSE
                WHEN status IN ('Ativo', 'Minuta', 'PreAssinaturas') THEN TRUE
                ELSE NULL
            END AS is_active,
            ts_signed,
            ts_created,
            ts_updated
        FROM
            core_contract.contract
    )
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_owner AS id_user,
        entity,
        'OWNER' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        contract_base
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_tenant AS id_user,
        entity,
        CASE
            WHEN ts_signed IS NOT NULL THEN 'TENANT'
            ELSE 'TENANT_PROSPECT'
        END AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        contract_base
),
termination AS (
  WITH termination_base AS (
    SELECT
      id AS id_entity,
      id_contract,
      'FR_TERMINATION' AS entity,
      'RENT' AS business_context,
      TO_JSON(
        STRUCT(
          status AS status,
          ts_created AS when
        )
      ) AS properties,
      CASE
          WHEN status IN ('DONE', 'CANCELED') THEN FALSE
          WHEN status IN (
            'REQUESTED',
            'INSPECTION_UNDER_REVIEW',
            'INSPECTION_SCHEDULED',
            'INSPECTION_OPTED_OUT',
            'INSPECTION_EXECUTED',
            'INSPECTION_CANCELED'
          ) THEN TRUE
          ELSE NULL
      END AS is_active,
      ts_created,
      ts_updated
    FROM datalake_terminator_clean.termination
  )
  SELECT
        tb.id_entity,
        c.id_house,
        c.id_owner AS id_user,
        c.id_contract AS id_contract,
        tb.entity,
        'OWNER' AS persona,
        tb.business_context,
        tb.properties,
        tb.is_active,
        tb.ts_created,
        tb.ts_updated
  FROM
        termination_base tb
  INNER JOIN
        core_contract.contract c
        ON tb.id_contract = c.id_contract
  UNION ALL
  SELECT
    tb.id_entity,
    c.id_house,
    c.id_tenant AS id_user,
    c.id_contract AS id_contract,
    tb.entity,
    'TENANT' AS persona,
    tb.business_context,
    tb.properties,
    tb.is_active,
    tb.ts_created,
    tb.ts_updated
  FROM
        termination_base tb
  INNER JOIN
        core_contract.contract c
        ON tb.id_contract = c.id_contract
),
listing AS (
    WITH last_contract AS (
        SELECT
            id_house,
            id_contract
        FROM
            core_contract.contract
        QUALIFY
            ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY ts_created DESC) = 1
    ),
    listing_base AS (
        SELECT
            lbc.id AS id_entity,
            lbc.id_house,
            IF(lbc.business_context = 'RENT', c.id_contract, NULL) AS id_contract,
            h.id_user AS id_owner,
            'LISTING' AS entity,
            lbc.business_context,
            TO_JSON(
                STRUCT(
                    lbc.status AS status,
                    lbc.ts_created AS when
                )
            ) AS properties,
            CASE
                WHEN lbc.status IN ('PUBLISHED', 'EDITING')
                    OR (lbc.status = 'SUSPENDED'
                        AND lbc.status_reason NOT IN ('OWNER_GAVE_UP_RENTING', 'OwnerConsequencesManagement', 'OwnerReforming', 'OwnerTemporarilySuspended', 'OwnerTraveling')) THEN TRUE
                WHEN lbc.status IN ('OPTED_OUT', 'UNPUBLISHED')
                    OR (lbc.status = 'SUSPENDED'
                        AND lbc.status_reason IN ('OWNER_GAVE_UP_RENTING', 'OwnerConsequencesManagement', 'OwnerReforming', 'OwnerTemporarilySuspended', 'OwnerTraveling')) THEN FALSE
                ELSE NULL
            END AS is_active,
            lbc.ts_created,
            lbc.ts_updated
        FROM
            datalake_ebdb_clean.listing_business_context AS lbc
        LEFT JOIN
            datalake_ebdb_clean.house AS h
                ON h.id = lbc.id_house
        LEFT JOIN
            last_contract AS c
                ON c.id_house = lbc.id_house
    )
    SELECT
        lb.id_entity,
        lb.id_house,
        lb.id_contract,
        lb.id_owner AS id_user,
        lb.entity,
        'OWNER' AS persona,
        lb.business_context,
        lb.properties,
        lb.is_active,
        lb.ts_created,
        lb.ts_updated
    FROM
        listing_base AS lb
),
inspection AS (
  WITH inspection_base AS (
    SELECT
      ib.id AS id_entity,
      ib.id_contract,
      ib.id_house,
      ib.id_user_inspector,
      c.id_owner,
      c.id_tenant,
      'FR_INSPECTION' AS entity,
      'RENT' AS business_context,
       TO_JSON(
        STRUCT(
          ib.status AS status,
          ib.dt_inspected AS when
        )
      ) AS properties,
      CASE
        WHEN ib.status IN ('Finalizada', 'Cancelada', 'ContratoCancelado') THEN FALSE
        WHEN ib.status IN ('Agendada', 'Comentada', 'EmAcordo', 'EmRevisao', 'Nova', 'Revisada') THEN TRUE
        ELSE NULL
      END AS is_active,
      ib.ts_created,
      ib.ts_updated
    FROM
        datalake_ebdb_clean.inspection AS ib
    INNER JOIN
        core_contract.contract AS c
            ON ib.id_contract = c.id_contract
    WHERE
        YEAR(ib.ts_created) >= 2025
  )
  SELECT
        ib.id_entity,
        ib.id_house,
        ib.id_owner AS id_user,
        ib.id_contract,
        ib.entity,
        'OWNER' AS persona,
        ib.business_context,
        ib.properties,
        ib.is_active,
        ib.ts_created,
        ib.ts_updated
    FROM
        inspection_base AS ib
    UNION ALL
    SELECT
      ib.id_entity,
      ib.id_house,
      ib.id_tenant AS id_user,
      ib.id_contract,
      ib.entity,
      'TENANT' AS persona,
      ib.business_context,
      ib.properties,
      ib.is_active,
      ib.ts_created,
      ib.ts_updated
    FROM
        inspection_base AS ib
    UNION ALL
    SELECT
      ib.id_entity,
      ib.id_house,
      ib.id_user_inspector AS id_user,
      ib.id_contract,
      ib.entity,
      'AGENT_INSPECTOR' AS persona,
      ib.business_context,
      ib.properties,
      ib.is_active,
      ib.ts_created,
      ib.ts_updated
    FROM
        inspection_base AS ib
),
credit_evaluation AS (
    WITH credit_evaluation_base AS (
        SELECT
            ce.id_credit_evaluation AS id_entity,
            ce.id_house,
            CAST(NULL AS BIGINT) AS id_contract,
            ce.id_user,
            ce.id_owner,
            'FR_CREDIT_EVALUATION' AS entity,
            'RENT' AS business_context,
            TO_JSON(
                STRUCT(
                    ce.status AS status,
                    ce.ts_created AS when
                )
            ) AS properties,
            CASE
                WHEN ce.status IN ('NOT_SENT', 'ON_HOLD', 'PROCESSING') THEN TRUE
                WHEN ce.status IN ('CANCELLED', 'FAILED', 'FINISHED') THEN FALSE
                ELSE NULL
            END AS is_active,
            ce.ts_created,
            ce.ts_updated
        FROM
            core_credit_evaluation.credit_evaluation AS ce
        )
    SELECT
        ce.id_entity,
        ce.id_house,
        ce.id_owner AS id_user,
        ce.id_contract,
        ce.entity,
        'OWNER' AS persona,
        ce.business_context,
        ce.properties,
        ce.is_active,
        ce.ts_created,
        ce.ts_updated
    FROM
        credit_evaluation_base AS ce
    UNION ALL
    SELECT
        ce.id_entity,
        ce.id_house,
        ce.id_user,
        ce.id_contract,
        ce.entity,
        'TENANT_PROSPECT' AS persona,
        ce.business_context,
        ce.properties,
        ce.is_active,
        ce.ts_created,
        ce.ts_updated
    FROM
        credit_evaluation_base AS ce
),
onboarding AS (
    WITH onboarding_base AS (
        SELECT
            id_entity,
            id_house,
            id_contract,
            id_owner,
            id_tenant,
            entity,
            business_context,
            TO_JSON(
                STRUCT(
                    status AS status,
                    ts_created AS when
                )
            ) AS properties,
            is_active,
            ts_created,
            ts_updated
        FROM
            datalake_entities_views.onboarding
        WHERE
            YEAR(ts_created) >= 2025
    )
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_owner AS id_user,
        entity,
        'OWNER' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        onboarding_base
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_tenant AS id_user,
        entity,
        'TENANT' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        onboarding_base
),
reservation AS (
    WITH reservation_base AS (
        SELECT
            rv.id AS id_entity,
            rv.id_house,
            rv.id_tenant,
            COALESCE(u.id, h.id_user) AS id_owner,
            CAST(NULL AS BIGINT) AS id_contract,
            'FR_RESERVATION' AS entity,
            'RENT' AS business_context,
            TO_JSON(
                STRUCT(
                    rv.status AS status,
                    rv.ts_created AS when
                )
            ) AS properties,
            IF(rv.is_ongoing = TRUE, TRUE, FALSE) is_active,
            rv.ts_created,
            rv.ts_updated
        FROM
            datalake_kill_queue_clean.reservation AS rv
        LEFT JOIN   -- To be replaced with House Core Model
            datalake_ebdb_clean.house AS h
                ON h.id = rv.id_house
        LEFT JOIN
            datalake_ebdb_clean.house_listing_relation AS hl
                ON hl.id = rv.id_house
                AND hl.related_as = 'PROPERTY_OWNER'
        LEFT JOIN
            datalake_ebdb_clean.user AS u
                ON (u.id = hl.id_related
                OR u.uuid_person = hl.id_related)
    )
    SELECT
        rb.id_entity,
        rb.id_house,
        rb.id_contract,
        rb.id_tenant AS id_user,
        rb.entity,
        'TENANT_PROSPECT' AS persona,
        rb.business_context,
        rb.properties,
        rb.is_active,
        rb.ts_created,
        rb.ts_updated
    FROM
        reservation_base AS rb
    UNION ALL
    SELECT
        rb.id_entity,
        rb.id_house,
        rb.id_contract,
        rb.id_owner AS id_user,
        rb.entity,
        'OWNER' AS persona,
        rb.business_context,
        rb.properties,
        rb.is_active,
        rb.ts_created,
        rb.ts_updated
    FROM
        reservation_base AS rb
),
repair AS (
    WITH ongoing_repair AS (
        SELECT
            rr.id AS id_entity,
            rr.id_house,
            rr.id_contract,
            'FR_REPAIR_ONGOING' AS entity,
            'RENT' AS business_context,
            TO_JSON(
                STRUCT(
                    rr.status AS status,
                    rr.ts_created AS when
                )
            ) AS properties,
            CASE
                WHEN rr.status IN ('AWAITING_BUDGET', 'AWAITING_BUDGET_APPROVAL', 'AWAITING_OWNER_ACTION', 'BUDGETING_IN_PROGRESS', 'COMPULSORY', 'IN_EXECUTION', 'IN_NEGOTIATION', 'IN_PROGRESS', 'REQUESTED', 'TENANT_NEEDS_CX_HELP', 'NULL') THEN TRUE
                WHEN rr.status IN ('FINISHED', 'RESOLVED', 'CANCELED') THEN FALSE
                ELSE NULL
            END AS is_active,
            rr.ts_created,
            rr.ts_updated
        FROM
            datalake_repairs_clean.repair_request AS rr
        WHERE
            rr.year >= 2025
            AND rr.status IS NOT NULL
    ),
    offboarding_repair AS (
        SELECT
            rr.id_repair_request AS id_entity,
            ins.id_contract,
            ins.id_inspector,
            'FR_REPAIR_OFFBOARDING' AS entity,
            'RENT' AS business_context,
            TO_JSON(
                STRUCT(
                    rr.ts_created AS when
                )
            ) AS properties,
            IF(rr.is_finished = TRUE, FALSE, TRUE) AS is_active,
            rr.ts_created,
            rr.ts_updated
        FROM
            datalake_inspection_services_clean.repair_request AS rr
        LEFT JOIN
            datalake_inspection_services_clean.item_group AS ig
                ON rr.id_item_group = ig.id_item_group
        LEFT JOIN
            datalake_inspection_services_clean.room AS ro
                ON ro.id_room = ig.id_room
        LEFT JOIN
            datalake_inspection_services_clean.assessment AS asm
                ON asm.id_assessment = ro.id_assessment
        LEFT JOIN
            datalake_inspection_services_clean.inspection AS ins
                ON ins.id_inspection = asm.id_inspection
        WHERE
            rr.year >= 2025
    ),
    union_all AS (
        SELECT 
            id_entity,
            id_house,
            id_contract,
            CAST(NULL AS STRING) AS id_inspector,
            entity,
            business_context,
            properties,
            is_active,
            ts_created,
            ts_updated
        FROM
            ongoing_repair
        UNION ALL
        SELECT
            id_entity,
            CAST(NULL AS BIGINT) AS id_house,
            id_contract,
            id_inspector,
            entity,
            business_context,
            properties,
            is_active,
            ts_created,
            ts_updated
        FROM
            offboarding_repair
    ),
    personas_base AS (
        SELECT
            ua.id_entity,
            COALESCE(ua.id_house, c.id_house) AS id_house,
            ua.id_contract,
            c.id_tenant,
            c.id_owner,
            ua.id_inspector,
            ua.entity,
            ua.business_context,
            ua.properties,
            ua.is_active,
            ua.ts_created,
            ua.ts_updated
        FROM
            union_all AS ua
        JOIN
            core_contract.contract AS c
                ON ua.id_contract = c.id_contract
    )
    SELECT
        pb.id_entity,
        pb.id_house,
        pb.id_contract,
        pb.id_owner AS id_user,
        pb.entity,
        'OWNER' AS persona,
        pb.business_context,
        pb.properties,
        pb.is_active,
        pb.ts_created,
        pb.ts_updated
    FROM
        personas_base AS pb
    UNION ALL
    SELECT
        pb.id_entity,
        pb.id_house,
        pb.id_contract,
        pb.id_tenant AS id_user,
        pb.entity,
        'TENANT' AS persona,
        pb.business_context,
        pb.properties,
        pb.is_active,
        pb.ts_created,
        pb.ts_updated
    FROM
        personas_base AS pb
    UNION ALL
    SELECT
        pb.id_entity,
        pb.id_house,
        pb.id_contract,
        pb.id_inspector AS id_user,
        pb.entity,
        'AGENT_INSPECTOR' AS persona,
        pb.business_context,
        pb.properties,
        pb.is_active,
        pb.ts_created,
        pb.ts_updated
    FROM
        personas_base AS pb
    WHERE
        entity = 'FR_REPAIR_OFFBOARDING'
),
base AS (
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        offer
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        contract
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        termination
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        listing
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        inspection
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        credit_evaluation
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        onboarding
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        reservation
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        repair
)
SELECT
    b.sk_entity,
    b.id_entity,
    b.id_house,
    b.id_contract,
    b.id_user,
    u.uuid_person,
    b.entity,
    b.persona,
    b.business_context,
    b.properties,
    {house_address} AS house_address,
    b.is_active,
    CASE
        WHEN b.is_active = FALSE THEN b.ts_updated
        ELSE NULL
    END AS ts_inactive,
    b.ts_created,
    b.ts_updated
FROM
    base AS b
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON h.id = b.id_house
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON u.id = b.id_user
WHERE
    b.id_user IS NOT NULL
    AND b.persona IS NOT NULL
