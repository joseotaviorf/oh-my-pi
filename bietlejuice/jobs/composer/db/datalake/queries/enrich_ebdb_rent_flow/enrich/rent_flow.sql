WITH rent_flow_offer_and_pre_proposal AS (
    WITH pre_proposal_with_visits AS (
        SELECT
            pp.id AS id_pp,
            booking.id AS id_booking,
            unix_timestamp(pp.ts_created) - unix_timestamp(booking.ts_created) AS creation_diff
        FROM datalake_ebdb_clean.pre_proposal pp
        JOIN datalake_ebdb_clean.booking
            ON booking.id_visitor = pp.id_user
            AND booking.id_house = pp.id_house
        WHERE pp.last_edition_updated > 0
            AND booking.type = 'Visita'
    ),
    pre_proposal_creation_diff AS (
        SELECT
            id_pp,
            COALESCE(
                MIN(IF(creation_diff >= 0, creation_diff, NULL)),
                MAX(IF(creation_diff < 0, creation_diff, NULL))
            ) AS min_diff
        FROM pre_proposal_with_visits
        GROUP BY 1
    ),
    pre_proposal_min_diff_booking AS (
        SELECT
            pp.id_pp,
            pp.id_booking
        FROM pre_proposal_with_visits pp
        JOIN pre_proposal_creation_diff pp_diff
            ON pp_diff.id_pp = pp.id_pp
            AND pp_diff.min_diff = pp.creation_diff
    ),
    agent_absent AS (
        SELECT DISTINCT
            id_booking,
            absence_reason = 'Absent' AS was_agent_absent
        FROM
            datalake_ebdb_clean.visitor
        WHERE type='Agent'
            AND absence_reason = 'Absent'
    ),
    rent_flow_pre_proposal_full AS (
        SELECT
            house.id AS id_house,
            booking.id AS id_booking,
            rf.id AS id_rent_flow,
            CASE
                WHEN prep_bk.id_pp  IS NOT NULL
                    THEN IF(prep_bk.id_pp != prep.id OR (prep_bk.id_pp != prep.id)  IS NULL, NULL, prep_bk.id_pp)
                WHEN prep.id IS NOT NULL AND booking.id IS NOT NULL
                    THEN NULL
                ELSE prep.id
            END AS id_pre_proposal,
            COALESCE(proposal_bk.id, proposal_pp.id) AS id_proposal,
            COALESCE(proposal_bk.ts_approved, proposal_pp.ts_approved) AS dt_proposal_approved,
            contract.id AS id_contract,
            contract.ts_created AS dt_contract_created,
            contract.ts_signed AS dt_contract_signed,
            contract.dt_termination AS dt_contract_annulment
        FROM datalake_ebdb_clean.house
        JOIN datalake_ebdb_clean.rent_flow rf
            ON house.id = rf.id_house
        LEFT JOIN datalake_ebdb_clean.booking
            ON rf.id = booking.id_rent_flow
            AND booking.type = 'Visita'
        LEFT JOIN datalake_ebdb_clean.user
            ON user.id = rf.id_client
        LEFT JOIN datalake_ebdb_clean.visit
            ON visit.id = booking.id_visit
        LEFT JOIN datalake_ebdb_clean.visit_origin vo_cr
            ON vo_cr.id = visit.id_creation_origin
        LEFT JOIN datalake_ebdb_clean.visit_origin vo_up
            ON vo_up.id = visit.id_last_update_origin
        LEFT JOIN datalake_ebdb_clean.user user_agent
            ON user_agent.id_agent = booking.id_agent
        LEFT JOIN datalake_ebdb_clean.pre_proposal prep
            ON prep.id_user = rf.id_client
            AND prep.id_house = rf.id_house
            AND prep.last_edition_updated > 0
        LEFT JOIN pre_proposal_min_diff_booking prep_bk
            ON prep_bk.id_booking = booking.id
        LEFT JOIN datalake_ebdb_clean.proposal proposal_pp
            ON proposal_pp.id_pre_proposal = prep.id
        LEFT JOIN datalake_ebdb_clean.proposal proposal_bk
            ON proposal_bk.id_pre_proposal = prep_bk.id_pp
        LEFT JOIN datalake_ebdb_clean.contract
            ON contract.id_proposal = COALESCE(proposal_bk.id, proposal_pp.id)
        LEFT JOIN datalake_ebdb_clean.portability
            ON portability.id_flow = rf.id
        LEFT JOIN agent_absent
            ON agent_absent.id_booking = booking.id
        WHERE ((prep_bk.id_pp = prep.id) IS NULL
            OR prep_bk.id_pp = prep.id)
            AND portability.id IS NULL
    ),
    rent_flow_pre_proposal AS (
        SELECT DISTINCT
            id_house,
            id_booking,
            id_rent_flow,
            id_pre_proposal,
            IF(id_pre_proposal IS NULL, NULL, id_proposal) AS id_proposal,
            IF(id_pre_proposal IS NULL, NULL, dt_proposal_approved) AS dt_proposal_approved,
            IF(id_pre_proposal IS NULL, NULL, id_contract) AS id_contract,
            IF(id_pre_proposal IS NULL, NULL, dt_contract_created) AS dt_contract_created,
            IF(id_pre_proposal IS NULL, NULL, dt_contract_signed) AS dt_contract_signed,
            IF(id_pre_proposal IS NULL, NULL, dt_contract_annulment) AS dt_contract_annulment
        FROM rent_flow_pre_proposal_full
    ),
    offer_with_visits AS (
        SELECT
            offer.id AS id_offer,
            booking.id AS id_booking,
            unix_timestamp(offer.ts_created) - unix_timestamp(booking.ts_created) AS creation_diff
        FROM datalake_ebdb_clean.offer
        JOIN datalake_ebdb_clean.booking
            ON booking.id_rent_flow = offer.id_rent_flow
        WHERE offer.ts_expired IS NOT NULL
            AND booking.type = 'Visita'
    ),
    offer_creation_diff AS (
        SELECT
            id_offer,
            COALESCE(
                MIN(IF(creation_diff >= 0, creation_diff, NULL)),
                MAX(IF(creation_diff < 0, creation_diff, NULL))
            ) AS min_diff
        FROM offer_with_visits
        GROUP BY 1
    ),
    offer_min_diff_booking AS (
        SELECT
            offer_with_visits.id_offer,
            offer_with_visits.id_booking
        FROM offer_with_visits
        JOIN offer_creation_diff of_diff
            ON of_diff.id_offer = offer_with_visits.id_offer
            AND of_diff.min_diff = offer_with_visits.creation_diff
    ),
    rent_flow_offer_full AS (
        SELECT
            house.id AS id_house,
            house.dt_first_publication AS dt_house_first_listing,
            booking.id AS id_booking,
            booking.ts_created AS dt_booking_created,
            booking.dt_booking AS dt_visit,
            COALESCE(
                booking.visit_fup IN ('VaiNegociar',
                                      'NaoGostou',
                                      'VisitouSozinho',
                                      'Talvez'),
                FALSE
            ) AS is_visit_completed,
            IF(
                booking.visit_fup IS NULL,
                FALSE,
                IF(
                    agent_absent.was_agent_absent,
                    FALSE,
                    TRUE
                )
            ) AS is_visit_performed,
            house.id_user AS id_owner,
            user_agent.id AS id_user_agent,
            rf.id_client,
            user.ts_created AS dt_client_sign_up,
            user_agent.ts_created AS dt_agent_sign_up,
            visit.id AS id_visit,
            vo_cr.is_app AS is_visit_created_from_app,
            vo_cr.name AS visit_created_type,
            COALESCE(vo_up.is_app, FALSE) AS is_visit_last_updated_from_app,
            rf.id AS id_rent_flow,
            rf.ts_created AS dt_rent_flow_created,
            CASE
                WHEN offer_bk.id_offer  IS NOT NULL
                    THEN if(offer_bk.id_offer != offer.id OR (offer_bk.id_offer != offer.id)  IS NULL, NULL, offer_bk.id_offer)
                WHEN offer.id  IS NOT NULL AND booking.id  IS NOT NULL
                    THEN NULL
                ELSE offer.id
            END AS id_offer,
            NULL AS id_pre_proposal,
            COALESCE(proposal_bk.id, proposal_off.id) AS id_proposal,
            COALESCE(proposal_bk.ts_approved, proposal_off.ts_approved) AS dt_proposal_approved,
            contract.id AS id_contract,
            contract.ts_created AS dt_contract_created,
            contract.ts_signed AS dt_contract_signed,
            contract.dt_termination AS dt_contract_annulment
        FROM datalake_ebdb_clean.house
        JOIN datalake_ebdb_clean.rent_flow rf
            ON house.id = rf.id_house
        LEFT JOIN datalake_ebdb_clean.booking
            ON rf.id = booking.id_rent_flow
            AND booking.type = 'Visita'
        LEFT JOIN datalake_ebdb_clean.user
            ON user.id = rf.id_client
        LEFT JOIN datalake_ebdb_clean.visit
            ON visit.id = booking.id_visit
        LEFT JOIN datalake_ebdb_clean.visit_origin vo_cr
            ON vo_cr.id = visit.id_creation_origin
        LEFT JOIN datalake_ebdb_clean.visit_origin vo_up
            ON vo_up.id = visit.id_last_update_origin
        LEFT JOIN datalake_ebdb_clean.user user_agent
            ON user_agent.id_agent = booking.id_agent
        LEFT JOIN datalake_ebdb_clean.offer
            ON offer.id_rent_flow = rf.id
            AND offer.ts_expired IS NOT NULL
        LEFT JOIN offer_min_diff_booking offer_bk
            ON offer_bk.id_booking = booking.id
        LEFT JOIN datalake_ebdb_clean.proposal proposal_off
            ON proposal_off.id_offer = offer.id
        LEFT JOIN datalake_ebdb_clean.proposal proposal_bk
            ON proposal_bk.id_offer = offer_bk.id_offer
        LEFT JOIN datalake_ebdb_clean.contract
            ON contract.id_proposal = COALESCE(proposal_bk.id, proposal_off.id)
        LEFT JOIN datalake_ebdb_clean.portability
            ON portability.id_flow = rf.id
        LEFT JOIN agent_absent
            ON agent_absent.id_booking = booking.id
        WHERE ((offer_bk.id_offer = offer.id) IS NULL
            OR offer_bk.id_offer = offer.id)
            AND portability.id IS NULL
    ),
    rent_flow_offer AS (
        SELECT DISTINCT
            id_house,
            dt_house_first_listing,
            id_booking,
            dt_booking_created,
            dt_visit,
            is_visit_completed,
            is_visit_performed,
            id_owner,
            id_user_agent,
            id_client,
            dt_client_sign_up,
            dt_agent_sign_up,
            id_visit,
            is_visit_created_from_app,
            visit_created_type,
            is_visit_last_updated_from_app,
            id_rent_flow,
            dt_rent_flow_created,
            id_offer,
            id_pre_proposal,
            IF(id_offer IS NULL, NULL, id_proposal) AS id_proposal,
            IF(id_offer IS NULL, NULL, dt_proposal_approved) AS dt_proposal_approved,
            IF(id_offer IS NULL, NULL, id_contract) AS id_contract,
            IF(id_offer IS NULL, NULL, dt_contract_created) AS dt_contract_created,
            IF(id_offer IS NULL, NULL, dt_contract_signed) AS dt_contract_signed,
            IF(id_offer IS NULL, NULL, dt_contract_annulment) AS dt_contract_annulment
        FROM rent_flow_offer_full
    )
    SELECT
        o.id_house,
        o.id_booking,
        o.id_owner,
        o.id_user_agent,
        o.id_client,
        o.id_visit,
        o.id_rent_flow,
        o.id_offer,
        pp.id_pre_proposal,
        COALESCE(o.id_proposal, pp.id_proposal) AS id_proposal,
        COALESCE(o.id_contract, pp.id_contract) AS id_contract,
        o.visit_created_type,
        o.is_visit_created_from_app,
        o.is_visit_last_updated_from_app,
        o.is_visit_completed,
        o.is_visit_performed,
        COALESCE(o.dt_proposal_approved, pp.dt_proposal_approved) AS dt_proposal_approved,
        o.dt_house_first_listing,
        o.dt_booking_created,
        o.dt_visit,
        o.dt_client_sign_up,
        o.dt_agent_sign_up,
        o.dt_rent_flow_created,
        COALESCE(o.dt_contract_created, pp.dt_contract_created) AS dt_contract_created,
        COALESCE(o.dt_contract_signed, pp.dt_contract_signed) AS dt_contract_signed,
        COALESCE(o.dt_contract_annulment, pp.dt_contract_annulment) AS dt_contract_annulment
    FROM rent_flow_offer o
    LEFT JOIN rent_flow_pre_proposal pp
        ON pp.id_house = o.id_house
        AND pp.id_rent_flow = o.id_rent_flow
        AND IF(pp.id_booking IS NOT NULL, pp.id_booking = o.id_booking, TRUE)
),
contract_with_rent_flow_portability AS (
    SELECT
        contract.id_house AS id_house,
        NULL AS id_booking,
        house.id_user AS id_owner,
        NULL AS id_user_agent,
        rf.id_client AS id_client,
        NULL AS id_visit,
        rf.id AS id_rent_flow,
        proposal.id_offer AS id_offer,
        NULL AS id_pre_proposal,
        contract.id_proposal AS id_proposal,
        contract.id AS id_contract,
        NULL AS visit_created_type,
        NULL AS is_visit_created_from_app,
        NULL AS is_visit_last_updated_from_app,
        NULL AS is_visit_completed,
        NULL AS is_visit_performed,
        proposal.ts_approved AS dt_proposal_approved,
        house.dt_first_publication AS dt_house_first_listing,
        NULL AS dt_booking_created,
        NULL AS dt_visit,
        NULL AS dt_client_sign_up,
        NULL AS dt_agent_sign_up,
        rf.ts_created AS dt_rent_flow_created,
        contract.ts_created AS dt_contract_created,
        contract.ts_signed AS dt_contract_signed,
        contract.dt_termination AS dt_contract_annulment
    FROM datalake_ebdb_clean.contract
    JOIN datalake_ebdb_clean.rent_flow rf
        ON contract.id_house = rf.id_house
        AND contract.id_user = rf.id_client
    JOIN datalake_ebdb_clean.house
        ON house.id = rf.id_house
    JOIN datalake_ebdb_clean.portability
        ON portability.id_flow = rf.id
    LEFT JOIN datalake_ebdb_clean.proposal
        ON contract.id_proposal = proposal.id
    LEFT JOIN datalake_ebdb_clean.offer
        ON offer.id = proposal.id_offer
),
contract_with_rent_flow AS (
    SELECT
        contract.id_house AS id_house,
        NULL AS id_booking,
        house.id_user AS id_owner,
        NULL AS id_user_agent,
        rf.id_client AS id_client,
        NULL AS id_visit,
        rf.id AS id_rent_flow,
        proposal.id_offer AS id_offer,
        proposal.id_pre_proposal AS id_pre_proposal,
        contract.id_proposal AS id_proposal,
        contract.id AS id_contract,
        NULL AS visit_created_type,
        NULL AS is_visit_created_from_app,
        NULL AS is_visit_last_updated_from_app,
        NULL AS is_visit_completed,
        NULL AS is_visit_performed,
        proposal.ts_approved AS dt_proposal_approved,
        house.dt_first_publication AS dt_house_first_listing,
        NULL AS dt_booking_created,
        NULL AS dt_visit,
        NULL AS dt_client_sign_up,
        NULL AS dt_agent_sign_up,
        rf.ts_created AS dt_rent_flow_created,
        contract.ts_created AS dt_contract_created,
        contract.ts_signed AS dt_contract_signed,
        contract.dt_termination AS dt_contract_annulment
    FROM
        datalake_ebdb_clean.contract
    JOIN datalake_ebdb_clean.rent_flow rf
        ON contract.id_house = rf.id_house
        AND contract.id_user = rf.id_client
    JOIN datalake_ebdb_clean.house
        ON house.id = rf.id_house
    LEFT JOIN datalake_ebdb_clean.proposal
        ON contract.id_proposal = proposal.id
    WHERE (proposal.id  IS NULL) OR
        (
            proposal.id  IS NOT NULL
            AND proposal.id_offer  IS NULL
            AND proposal.id_pre_proposal  IS NULL
        )
),
all_rent_flows AS (
    SELECT * FROM rent_flow_offer_and_pre_proposal
    UNION
    SELECT * FROM contract_with_rent_flow_portability
    UNION
    SELECT * FROM contract_with_rent_flow
)
SELECT
    ROW_NUMBER() OVER ( ORDER BY 0 ) AS id_house_rent_flow,
    id_house,
    id_booking,
    id_owner,
    id_user_agent,
    id_client,
    id_visit,
    id_rent_flow,
    id_offer,
    id_pre_proposal,
    id_proposal,
    id_contract,
    visit_created_type,
    is_visit_created_from_app,
    is_visit_last_updated_from_app,
    is_visit_completed,
    is_visit_performed,
    dt_proposal_approved,
    dt_house_first_listing,
    dt_booking_created,
    dt_visit,
    dt_client_sign_up,
    dt_agent_sign_up,
    dt_rent_flow_created,
    dt_contract_created,
    dt_contract_signed,
    dt_contract_annulment
FROM all_rent_flows