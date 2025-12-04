SELECT
    id,
    photo_session_id AS id_photo_session,
    version,
    video,
    quantity_photos,
    same_day_listing,
    has_plaque,
    ticket_reference,
    status,
    plaque_status,
    responsible,
    plaque_responsible_approver,
    video_value,
    quantity_photos_value,
    source_status_update_at AS dt_source_status_update,
    publication_date AS dt_publication,
    uploaded_date AS dt_uploaded,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.photo_session_details

