SELECT
    id,
    loserAccountId AS id_loser_account,
    winnerAccountId AS id_winner_account,
    status,
    failureCount AS failure_count,
    criadoEm as ts_created,
    atualizadoEm as ts_updated
FROM
    datalake_ebdb_raw.usermerge
