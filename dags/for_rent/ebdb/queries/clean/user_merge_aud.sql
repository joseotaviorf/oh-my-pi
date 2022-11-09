SELECT
    id,
    loserAccountId AS id_loser_account,
    winnerAccountId AS id_winner_account,
    rev,
    revtype AS rev_type,
    failureCount AS failure_count,
    failureCount_MOD AS mod_failure_count,
    status,
    status_mod AS mod_status
FROM
    datalake_ebdb_raw.usermerge_aud
