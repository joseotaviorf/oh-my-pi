SELECT
    complete_name AS name,
    email,
    team,
    front_or_back,
    crm_access AS has_crm_access,
    magic_link_access AS has_magic_link_access,
    check_house_data_edition AS has_house_data_edition_access,
    update_bank_data AS has_bank_data_edition_access
FROM
    datalake_gsheets_raw.tool_access_mapping
