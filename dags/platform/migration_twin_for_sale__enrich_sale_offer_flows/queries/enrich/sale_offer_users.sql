WITH sales_flow_users AS (
    SELECT
        id_user,
        id_sales_flow,
        type,
        is_original_user,
        ts_created,
        ts_updated
    FROM
        datalake_sales_flow_clean.sales_flow_users
    ),
first_invite AS (
    SELECT
        id_sales_flow,
        id_inviter,
        id_invitee,
        type,
        ts_created
    FROM
        datalake_sales_flow_clean.sales_flow_invite_aud
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_sales_flow, id_invitee, type ORDER BY ts_created ASC) = 1
),
last_invite_update AS (
    SELECT
        id_sales_flow,
        id_inviter,
        id_invitee,
        type,
        ts_updated
    FROM
        datalake_sales_flow_clean.sales_flow_invite_aud
    WHERE
        status = "ACCEPTED"
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_sales_flow, id_inviter, id_invitee, type ORDER BY ts_updated DESC) = 1
),
sales_flow_invites AS (
    SELECT
        sfiaud.id_sales_flow,
        sfiaud.id_inviter, -- This ID relates to the id_user on table datalake_sales_flow_clean.users not the user id on EBDB
        sfiaud.id_invitee, -- This ID relates to the id_user on table datalake_sales_flow_clean.users not the user id on EBDB
        sfiaud.type,
        sfiaud.status,
        fi.ts_created AS ts_user_invited,
        liu.ts_updated AS ts_user_invite_accepted,
        sfiaud.ts_created,
        sfiaud.ts_updated
    FROM
        datalake_sales_flow_clean.sales_flow_invite_aud AS sfiaud
    LEFT JOIN
        first_invite AS fi
            ON fi.id_sales_flow = sfiaud.id_sales_flow
            AND fi.id_inviter = sfiaud.id_inviter
            AND fi.id_invitee = sfiaud.id_invitee
            AND fi.type = sfiaud.type
    LEFT JOIN
        last_invite_update AS liu
            ON liu.id_sales_flow = sfiaud.id_sales_flow
            AND liu.id_inviter = sfiaud.id_inviter
            AND liu.id_invitee = sfiaud.id_invitee
            AND liu.type = sfiaud.type
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY sfiaud.id_sales_flow, sfiaud.id_inviter, sfiaud.id_invitee, sfiaud.type ORDER BY sfiaud.ts_updated DESC) = 1
),
users_info AS (
    SELECT
        id AS id_user,
        id_external,
        name,
        email,
        phone,
        type,
        cpf,
        ts_created,
        ts_updated
    FROM
        datalake_sales_flow_clean.users
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1
),
sales_flow AS (
    SELECT
        id AS id_sales_flow,
        id_house
    FROM
        datalake_sales_flow_clean.sales_flow
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated DESC) = 1
),
sales_flow_house AS (
    SELECT
        id,
        id_external
    FROM
        datalake_sales_flow_clean.house
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated) = 1
),
offer AS (
    SELECT
        id_sales_flow,
        id_firestore
    FROM
        datalake_sales_flow_clean.offer
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated DESC) = 1
),
folder_reference_docx AS (
    SELECT
        fr.id,
        fo.id_external AS id_external,
        id_source_folder, -- id do usuario na tabela folder
        id_target_folder, --  id da house na tabela folder
        reference_properties,
        reference_properties:offerId AS id_offer,
        reference_properties:isCCVBuyer AS is_ccv_buyer,
        reference_properties:isCCVFlow AS is_ccv_flow,
        reference_properties:isIncomePartner AS is_income_partner,
        reference_properties:hasJointBuyer AS has_joint_buyer,
        reference_properties:inviteeList AS invitee_list,
        ts_documentation_sent
    FROM
        datalake_docx_clean.folder_reference AS fr
    LEFT JOIN
        datalake_docx_clean.folder AS fo
            ON fr.id_source_folder = fo.id
),
house_folder_reference AS (
    SELECT
        id_target_folder, --  id da house na tabela folder
        fo.id_external,
        reference_properties:offerId AS id_offer
    FROM
        datalake_docx_clean.folder_reference AS fr
    LEFT JOIN
        datalake_docx_clean.folder AS fo
            ON fr.id_target_folder = fo.id
    GROUP BY 1, 2, 3
),
buyer_data AS (
    SELECT
        id_buyer,
        id_sales_flow,
        id_docx_folder,
        name,
        email,
        holding_value,
        ccv_role,
        signer_status,
        ts_created,
        ts_updated,
        year,
        month,
        day
    FROM
        datalake_sales_flow_clean.buyer_data
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY email, id_sales_flow ORDER BY ts_updated DESC) = 1
),
seller_data AS (
    SELECT
        id_seller,
        id_sales_flow,
        id_docx_folder,
        name,
        email,
        share_percentage,
        holding_value,
        CAST(NULL AS STRING) AS party_kind,
        CAST(NULL AS STRING) AS is_on_register,
        CAST(NULL AS STRING) AS is_active,
        is_ccv_signer,
        CAST(NULL AS STRING) AS is_pj,
        ts_created,
        ts_updated
    FROM
        datalake_sales_flow_clean.seller_data
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY email, id_sales_flow ORDER BY ts_updated DESC) = 1
)
SELECT
    sfu.id_user,
    ui.id_external,
    off.id_firestore,
    sfh.id_external AS id_house,
    sfu.id_sales_flow,
    inv_ui.id_external AS id_inviter,
    sfi.id_invitee,
    hfr.id_target_folder AS id_house_docx_folder,
    COALESCE(byd.id_docx_folder, sld.id_docx_folder, frd.id_source_folder) AS id_user_docx_folder,
    sfu.type,
    sfi.status AS invite_status,
    ui.name,
    ui.email,
    ui.phone,
    ui.cpf,
    byd.signer_status AS buyer_signer_status,
    byd.holding_value AS buyer_holding_value,
    sld.holding_value AS seller_holding_value,
    sld.share_percentage AS seller_share_percentage,
    sfu.is_original_user,
    CAST(frd.is_ccv_buyer AS BOOLEAN) AS is_ccv_buyer,
    sld.is_ccv_signer AS is_seller_ccv_signer,
    CAST(frd.is_income_partner AS BOOLEAN) AS is_income_partner,
    sld.is_pj,
    sld.is_active,
    sld.is_on_register AS is_seller_on_register,
    CAST(frd.is_ccv_flow AS BOOLEAN) AS is_ccv_flow,
    CAST(frd.has_joint_buyer AS BOOLEAN) AS has_joint_buyer,
    sfi.ts_user_invited,
    sfi.ts_user_invite_accepted,
    sfu.ts_updated
FROM
    sales_flow_users AS sfu
LEFT JOIN
    users_info AS ui
        ON ui.id_user = sfu.id_user
LEFT JOIN
    sales_flow_invites AS sfi
        ON sfi.id_sales_flow = sfu.id_sales_flow
        AND sfi.id_invitee = sfu.id_user
LEFT JOIN
    users_info AS inv_ui
        ON inv_ui.id_user = sfi.id_inviter
LEFT JOIN
    offer AS off
        ON off.id_sales_flow = sfu.id_sales_flow
LEFT JOIN
    sales_flow AS sf
        ON sf.id_sales_flow = sfu.id_sales_flow
LEFT JOIN
    sales_flow_house AS sfh
        ON sfh.id = sf.id_house
LEFT JOIN
    folder_reference_docx AS frd
        ON frd.id_offer = off.id_firestore
        AND frd.id_external = ui.id_external
LEFT JOIN
    house_folder_reference AS hfr
        ON hfr.id_external = sfh.id_external
        AND hfr.id_offer = off.id_firestore
LEFT JOIN
    buyer_data AS byd
        ON byd.email = ui.email
        AND byd.id_sales_flow = sfu.id_sales_flow
LEFT JOIN
    seller_data AS sld
        ON sld.email = ui.email
        AND sld.id_sales_flow = sfu.id_sales_flow
