# EMR instance fleet autoscaling (`max_nodes`)

How to opt EMR **instance-fleet** clusters into **managed scaling** from `{dag}_cluster.yml`, and how that maps to the EMR API.

Implementation: [`template_translator.py`](../../packages/bietlejuice-airflow-operators/src/emr_plugin/template_translator.py) (`_build_fleet_managed_scaling_policy`, `_fleet_launch_targets`). Declaration validation: [`dag_cluster_validator.py`](../../packages/bietlejuice-core/src/bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_cluster_validator.py).

## When autoscaling is enabled

Managed scaling is **opt-in**. It is attached only when **either** `core_nodes.max_nodes` or `task_nodes.max_nodes` is set under `cluster.custom_configurations` (after merge with the preset in `prod_conf.yml` / `forno_conf.yml`).

If neither fleet sets `max_nodes`, the cluster stays **fixed size** at launch (`target_on_demand` + `target_spot` per fleet). No `ManagedScalingPolicy` is sent to `RunJobFlow`.

**Not supported on fleets:** top-level `autoscale` with CloudWatch `rules` (instance **groups** only). Fleets use EMR managed scaling exclusively.

## YAML shape

Fleet presets (`*_fleet_cluster`) define `core_nodes` / `task_nodes` with `instance_types`, `target_on_demand`, and `target_spot`. Consolidation presets often use **2 core on-demand** and **0/0 task** (task block is a placeholder with `instance_types` only).

Overrides **deep-merge** onto the preset. You can set only `max_nodes` without repeating targets or instance types:

```yaml
cluster:
  type: emr_7_12_consolidation_m_memory_fleet_cluster
  custom_configurations:
    core_nodes:
      max_nodes: 6
    task_nodes:
      max_nodes: 12
```

| Field | Role |
|--------|------|
| `target_on_demand` + `target_spot` | **Launch size** and **floor** for that fleet (units; weighted capacity is 1 in this repo) |
| `max_nodes` | **Ceiling** for that fleet under managed scaling |

Omit `max_nodes` on a fleet to **pin** it at the launch targets (typical for core when only task should grow).

## Spot vs on-demand scale-out

The **market** for extra capacity follows the fleet’s launch targets, not a separate `max_spot` / `max_on_demand`:

| Launch pattern | Scale-out market |
|----------------|------------------|
| On-demand only (`target_on_demand` > 0, `target_spot` = 0) | On-demand |
| Spot only | Spot |
| Mixed | Roughly the same on-demand/spot ratio up to `max_nodes` (via `MaximumOnDemandCapacityUnits` in the policy) |
| Task preset **0/0** + `max_nodes` only | `aws_attributes.task_availability` on the preset (consolidation default **SPOT**) |

For a full task fleet block, set `target_on_demand` / `target_spot` explicitly instead of relying on `task_availability`.

## EMR create-time constraint (0/0 task preset)

AWS rejects a task fleet whose **both** `targetOnDemandCapacity` and `targetSpotCapacity` are **0** on `RunJobFlow`.

When YAML leaves task at **0/0** but `max_nodes` (or fleet emission) requires a TASK fleet, the translator sets **launch** to **1 unit** on the scale-out market (1 spot by default, or 1 on-demand when `task_availability` is `ON_DEMAND`). Managed scaling **minimum** includes that unit. This is **not** a preset change; presets may keep `target_spot: 0`.

To start with more than one task node in YAML, set targets explicitly, for example `target_spot: 2` and `max_nodes: 12`.

## Core fleet rules

- **CORE** must have `target_on_demand + target_spot >= 1` when using `max_nodes` (validator and translator).
- **CORE** cannot scale from zero with `max_nodes` alone (validator rejects 0/0 core even with `max_nodes`).
- **TASK** may use 0/0 in YAML with `max_nodes` (scale-from-zero at the policy level; launch still ≥ 1 unit at create).

## What triggers scaling (runtime)

`ManagedScalingPolicy` only sets **limits** (`ComputeLimits` with `UnitType: InstanceFleetUnits`). **Amazon EMR** evaluates YARN-related metrics on a short interval and resizes fleets via `ModifyInstanceFleet`. This repo does **not** configure CloudWatch alarm thresholds for fleets.

Spark jobs should leave **dynamic allocation** enabled (EMR presets do by default). The translator logs a warning if `spark.dynamicAllocation.enabled` is false or `spark.dynamicAllocation.maxExecutors` is capped, because scaling may not occur.

## Verify on a run

1. Trigger the DAG on Forno/prod after merge.
2. In the EMR cluster console, open **Managed scaling** and confirm `InstanceFleetUnits` and min/max match expectations.
3. In CloudWatch (EMR namespace), inspect `CoreUnitsRequested`, `TaskUnitsRequested`, and YARN pending metrics if you expect scale-out.

For a local check of the job flow dict, unit tests in `packages/bietlejuice-airflow-operators/test/test_template_translator.py` cover policy shape and launch targets.

## Related docs

- [Cluster validation DAGs](cluster_validation_dags.md) — `validation.cluster` and preset merge (validation blocks do not carry Databricks `autoscale`; fleet `max_nodes` is prod-only unless you add it to validation explicitly).
- [EMR observability](emr_observability.md) — cost and fleet timeline after the cluster is up.
- [DAG Builder — EMR fleets](../.cursor/rules/dag_build.mdc) — declaration patterns next to instance groups.
