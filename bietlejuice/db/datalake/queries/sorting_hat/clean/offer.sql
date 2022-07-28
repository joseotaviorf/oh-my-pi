select
    id,
    type,
    timestamp(approved_at) as ts_approved,
    firestore_id as id_firestore,
    proposal_id as id_proposal
from datalake_sorting_hat_raw.offer