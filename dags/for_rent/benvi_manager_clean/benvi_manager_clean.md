# benvi_manager_clean

Reads `datalake_benvi_manager_raw.lake_mirror` (filled by `bietlejuice.benvi_manager`)
and writes one clean table per Superlogica `resource_code`, plus exploded nested
arrays and join projections for financial resources.

## Trigger

No cron. `schedule_interval` is omitted so DAG Builder attaches the dataset
schedule from `dags/dependencies.yaml`.

Runs when `bietlejuice.benvi_manager:load-clean-lake-mirror` is emitted (plain
URI, every successful CDC load, not first-run-of-day). UI Trigger DAG still
works if you need an isolated projection rebuild.

Raw CDC is a single table (`lake_mirror`). There is no per-`resource_code`
dataset. The existing edge already covers CHARGE, CONTRACT_EXPENSE, PAYOUT,
AGREEMENT, and DELINQUENCY once those rows land.

## Resource tables (RAW sheet names)

| Clean table | `resource_code` | RAW sheet | PK |
|---|---|---|---|
| `benvi_superlogica_cobranca` | CHARGE | cobrancas_full | `id_recebimento_recb` |
| `benvi_superlogica_despesa_atual` | CONTRACT_EXPENSE | despesas_atuais | `id_lancamento_imod` |
| `benvi_superlogica_despesa_imovel_vago` | VACANT_PROPERTY_EXPENSE | vacants | `id_lancamento_imod` |
| `benvi_superlogica_despesa` | both expense codes | despesas_full | `id_lancamento_imod` (CONTRACT_EXPENSE wins on clash) |
| `benvi_superlogica_repasse` | PAYOUT | repasses | `id_repasse_rep` |
| `benvi_superlogica_acordo` | AGREEMENT | acordos | `id_acordo_aco \| id_recebimento_recb` |
| `benvi_superlogica_inadimplencia` | DELINQUENCY | inadimplencia | `id_pessoa_pes \| id_contrato_con` |

## Support tickets and departments

| Clean table | `resource_code` | RAW sheet | PK |
|---|---|---|---|
| `benvi_superlogica_ticket` | TICKET | tickets | `id_ticket_tic` |
| `benvi_superlogica_ticket_historico` | TICKET_HISTORY | ticket_historico | `id_ticket_tic \| id_historico_tih` |
| `benvi_superlogica_departamento` | USER_GROUP | departamentos | `st_nome_grpu` (no vendor id on the list endpoint) |

Ticket history is a fan-out keyed per ticket, so its `vendor_natural_key` is the
cursor-resolved parent ticket id piped with `id_historico_tih`. History ids repeat
across tickets, so only the composite is unique. Same shape as
`benvi_superlogica_manutencao_historico`: split the key, no join in the projection.

`USER_GROUP` has no id on `GET /grupousuarios`, so the group name is the key. The
vendor still ships `id_grupo_grpu` inside the payload as an unmapped field, and that
is what `benvi_superlogica_ticket.id_grupo_tic` points at.

All three project every field the vendor puts in `payload`, including the ones the
SDK row models do not map explicitly and which reach `payload` through unmapped-field
capture. Person names and contact channels are projected like the debtor columns on
`benvi_superlogica_cobranca`: the column lives on clean and Trino column-level ACL is
the access control. The only fields missing from `payload` at all are
`st_apptoken_usu` and `st_linksenha_usu`, which `SuperlogicaSensitiveVendorFieldDenylist`
strips upstream before landing.

## Nested arrays (explode, not extra extractors)

| Clean table | Parent payload array |
|---|---|
| `benvi_superlogica_cobranca_componente` | CHARGE `compo_recebimento` |
| `benvi_superlogica_despesa_movimentacao` | CONTRACT_EXPENSE `movimentacoes` |
| `benvi_superlogica_despesa_repasse` | CONTRACT_EXPENSE `repasses` |
| `benvi_superlogica_repasse_item` | PAYOUT `repasse_item` |
| `benvi_superlogica_repasse_beneficiario` | PAYOUT `proprietarios_beneficiarios` |

## Joins on clean

- CHARGE `id_contrato_con` -> contrato; CHARGE `id_sacado_sac` -> locatario.`id_sacado_sac` (not `id_pessoa_pes`).
- PAYOUT `id_contrato_con` -> contrato; `id_recebimento_recb` -> cobranca; `id_locatario_pes` -> locatario.`id_pessoa_pes`.
- AGREEMENT `id_recebimento_recb` -> cobranca; `id_acordo_aco` groups parcels; `id_sacado_sac` -> locatario.`id_sacado_sac`.
- DELINQUENCY left key -> locatario.`id_pessoa_pes`; right key -> contrato; `id_sacado_sac` from the row or the parent TENANT payload.

Existing CONTRACT/PROPERTY junctions (`contratos_inquilinos`, `imoveis_proprietarios`) stay explode-from those parents. This DAG does not add Superlogica HTTP calls.

DW spreadsheet roll-ups (`all_checklists`, ticket/checklist consolidations) stay out of this worker.
