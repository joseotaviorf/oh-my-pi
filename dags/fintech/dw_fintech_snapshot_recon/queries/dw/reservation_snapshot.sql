WITH proposal AS (
    SELECT
        flr.sk_rent_flow,
        dp.sk_proposal,
        dp.status AS proposal_status,
        dp.dt_updated AS proposal_dt_update,
        dp.rejection_reason AS proposal_rejection_reason,
        flr.sk_contract,
        ROW_NUMBER() OVER (
            PARTITION BY flr.sk_rent_flow
            ORDER BY dp.dt_updated DESC
        ) AS rn,
        COUNT(flr.sk_rent_flow) OVER (
            PARTITION BY flr.sk_rent_flow
        ) AS proposal_count
    FROM (
        SELECT DISTINCT
            sk_rent_flow,
            sk_proposal,
            sk_contract
        FROM dw_rent.fact_listing_rent_flows
        WHERE
            sk_proposal > 0
            AND sk_reservation <> -1
    ) AS flr
    LEFT JOIN dw_rent.dim_proposal AS dp
        ON dp.sk_proposal = flr.sk_proposal
),

contract AS (
    SELECT
        flr.sk_rent_flow,
        dc.sk_contract,
        CASE
            WHEN dc.ts_signature IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS contract_signed,
        dc.ts_signature AS dt_contract_signed,
        dc.ts_updated AS contract_dt_update,
        dc.status AS contract_status,
        dc.ts_created AS contract_created,
        dc.cancellation_reason AS contract_rejection_reason
    FROM (
        SELECT DISTINCT
            sk_rent_flow,
            sk_contract
        FROM dw_rent.fact_listing_rent_flows
        WHERE
            sk_contract > 0
            AND sk_reservation <> -1
    ) AS flr
    LEFT JOIN dw_rent.dim_contract AS dc
        ON dc.sk_contract = flr.sk_contract
),

historic_status AS (
    SELECT
        r_aud.id AS id_reservation,
        r_aud.status AS status_at_date,
        ROW_NUMBER() OVER (
            PARTITION BY r_aud.id
            ORDER BY ure.ts_rev DESC
        ) AS rn
    FROM datalake_kill_queue_clean.reservation_aud AS r_aud
    INNER JOIN datalake_kill_queue_clean.rev_info AS ure
        ON r_aud.rev = ure.rev
),

reservation AS (
    SELECT
        rf.sk_house_listing,
        dhl.id_house,
        rf.sk_client,
        rf.sk_rent_flow,
        r.status AS reservation_status_real,
        hs.status_at_date,
        r.sk_reservation,
        r.value,
        r.installments,
        MIN(DATE(r.ts_created)) AS reservation_date
    FROM dw_rent.dim_reservation AS r
    LEFT JOIN (
        SELECT DISTINCT
            sk_reservation,
            sk_rent_flow,
            sk_client,
            sk_house_listing
        FROM dw_rent.fact_listing_rent_flows
        WHERE sk_reservation > 0
    ) AS rf
        ON rf.sk_reservation = r.sk_reservation
    LEFT JOIN dw_rent.dim_house_listing AS dhl
        ON dhl.sk_house_listing = rf.sk_house_listing
    LEFT JOIN historic_status AS hs
        ON hs.id_reservation = r.sk_reservation
        AND hs.rn = 1
    GROUP BY
        rf.sk_house_listing,
        dhl.id_house,
        rf.sk_client,
        rf.sk_rent_flow,
        r.status,
        hs.status_at_date,
        r.sk_reservation,
        r.value,
        r.installments
)

SELECT DISTINCT
    r.sk_house_listing,
    r.id_house,
    r.sk_client,
    r.sk_rent_flow,
    r.reservation_status_real,
    r.status_at_date,
    r.sk_reservation,
    r.value,
    r.installments,
    r.reservation_date,
    DATE(DATE_TRUNC('month', r.reservation_date)) AS reservation_month,
    dhl.house_status AS house_status,
    du.nome,
    du.cpf,
    w.charge_status AS mundipagg_status,
    w.ts_updated AS mundipagg_updated_at,
    w.amount / 100.00 AS mundipagg_charged_amount,
    w.installments AS mundipagg_installments,
    p.sk_proposal,
    p.proposal_dt_update,
    p.proposal_status,
    p.proposal_rejection_reason,
    c.sk_contract,
    c.contract_signed,
    c.dt_contract_signed,
    c.contract_dt_update,
    c.contract_created,
    c.contract_status,
    c.contract_rejection_reason,
    CASE
        WHEN r.status_at_date = 'CHARGED'
            AND p.proposal_status = 'Aprovada'
            AND p.proposal_rejection_reason IS NULL
            AND c.contract_status IN ('Ativo', 'Finalizado')
            AND c.contract_rejection_reason IS NULL
            THEN 'FINISHED'
        WHEN r.status_at_date = 'CHARGED'
            AND p.proposal_status = 'Aprovada'
            AND p.proposal_rejection_reason IS NULL
            AND c.contract_status IN ('Cancelado')
            AND UPPER(c.contract_rejection_reason) IN (
                'OWNER_SELLING_HOUSE',
                'OWNER_PREFERS_OTHER',
                'SIG_DEADLINE_EXPIRED',
                'OWNER_RENTING_WITH_OTHER_COMPANY',
                'VALIDITY_DATES',
                'OWNER_GAVE_UP_RENTING',
                'INCORRECT_INFO',
                'DISAGREEMENT',
                'OTHERS',
                'TENANT_UNABLE_TO_LEAVE',
                'PRICE_MODIFICATION',
                'OWNER_DOESNT_AGREE'
            )
            THEN 'RETURNED'
        WHEN r.status_at_date = 'CHARGED'
            AND p.proposal_status = 'Aprovada'
            AND p.proposal_rejection_reason IS NULL
            AND c.contract_status IN ('Cancelado')
            AND UPPER(c.contract_rejection_reason) IN ('TENANT_GAVE_UP_RENTING')
            THEN 'CANCELED'
        WHEN r.status_at_date = 'CHARGED'
            AND p.proposal_status IS NULL
            AND p.proposal_rejection_reason IS NULL
            AND c.contract_status IS NULL
            AND c.contract_rejection_reason IS NULL
            THEN 'RETURNED'
        WHEN r.status_at_date = 'CHARGED'
            AND p.proposal_status IN ('Rejeitada')
            AND p.proposal_rejection_reason IN (
                'OwnerRentedForAnotherTenantOutside',
                'TenantDocumentationRejected',
                'HouseReserved',
                'OwnerGaveUpTenant',
                'OwnerStalled',
                'TenantFailedPayment',
                'OwnerGaveUpRenting',
                'HouseNotAvailable',
                'TenantNoReserved',
                'OwnerSoldApartment'
            )
            AND c.contract_status IS NULL
            AND c.contract_rejection_reason IS NULL
            THEN 'RETURNED'
        WHEN r.status_at_date = 'CHARGED'
            AND p.proposal_status IN ('Rejeitada')
            AND p.proposal_rejection_reason IN ('TenantStalled')
            AND c.contract_status IS NULL
            AND c.contract_rejection_reason IS NULL
            THEN 'CANCELED'
        ELSE r.status_at_date
    END AS reservation_status_final,
    p.proposal_count,
    CASE
        WHEN r.status_at_date IN ('CHARGED', 'WAITING_REFUND')
            AND DATEDIFF(CURRENT_DATE(), r.reservation_date) > 30
            THEN TRUE
        ELSE FALSE
    END AS charged_more_then_30_days,
    NOW() AS ts_snapshot,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM reservation AS r
LEFT JOIN dw_public.dim_user AS du
    ON du.sk_user = r.sk_client
LEFT JOIN dw_rent.dim_house_listing AS dhl
    ON dhl.sk_house_listing = r.sk_house_listing
LEFT JOIN proposal AS p
    ON p.sk_rent_flow = r.sk_rent_flow
    AND p.rn = 1
LEFT JOIN contract AS c
    ON c.sk_rent_flow = p.sk_rent_flow
    AND c.sk_contract = p.sk_contract
LEFT JOIN datalake_kill_queue_clean.charge AS ca
    ON ca.id_reservation = r.sk_reservation
LEFT JOIN datalake_wall_street_clean.charge AS w
    ON w.code = ca.id
WHERE
    r.status_at_date = 'CHARGED'
    AND w.id_store = 5
    AND w.id_acquire_transaction <> '-1'
    AND DATE(w.ts_updated) >= DATE('2015-01-01')
    AND DATE(w.ts_updated) <= CURRENT_DATE
