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
