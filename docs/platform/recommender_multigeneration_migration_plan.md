# Cluster Spec Recommender - Multi-Generation Migration Plan

Implementation spec for making [`scripts/recommend_cluster_specs.py`](../../scripts/recommend_cluster_specs.py)
**generation-aware** so it can target ARM Graviton generations beyond Gen 6
(Graviton2): Gen 7 (Graviton3) fleet-wide and Gen 8 (Graviton4) selectively.

This document is **decision-complete**: a later agent executes it with no open
design choices. It changes no code itself.

Companion analysis (the *why*, with live numbers and the t-shirt comparison
tables): [`spark_instance_generation_analysis.html`](spark_instance_generation_analysis.html).
Algorithm reference: [`cluster_spec_recommender_algorithm.md`](cluster_spec_recommender_algorithm.md).
Operational gates: [`cluster_spec_recommender_runbook.md`](cluster_spec_recommender_runbook.md).

---

## 1. Why this is needed (problem statement)

The recommender and the Databricks cluster presets are **structurally pinned to
Gen 6**, so the ~9-12% total-cost win from moving the fleet to Gen 7 is
currently unreachable by the tool, even though Gen 7 is already vetted in the
repo (the EMR side runs `emr_7_12_consolidation_*` on c7g/m7g/r7g).

Three concrete pins, with exact anchors (verified against the current tree):

1. **Family→node builder hardcodes Gen 6.**
   [`_node_for_family_tier`](../../scripts/recommend_cluster_specs.py) at
   `scripts/recommend_cluster_specs.py:600-602`:
   ```python
   def _node_for_family_tier(family: str, tier: str) -> str:
       prefix_by_family = {"compute": "c6g", "general": "m6g", "memory": "r6g"}
       return f"{prefix_by_family[family]}.{_TIER_TO_SIZE[tier]}"
   ```
   Every preset-tier node it emits is `c6g`/`m6g`/`r6g`.

2. **Sizing picks the cheapest `$/hr`, so Gen 6 always wins at equal capacity.**
   - `_single_node_candidates` (`scripts/recommend_cluster_specs.py:631-642`)
     enumerates every ARM node and sorts by `(price, memory_gb, vcpus)`.
   - `_node_for_demand` (`scripts/recommend_cluster_specs.py:704-727`) filters to
     nodes that hold demand at the 82% memory / 85% CPU targets and then takes
     `min(..., key=lambda item: (item[2], item[1].memory_gb, item[1].vcpus))`.
   Because a newer generation costs ~6% (Gen6→7) / ~10% (Gen7→8) more at the
   *same* vCPU/RAM, the cheapest-`$/hr` comparator can never select it — even
   though the newer node finishes the same work faster.

3. **The cost engine never credits a faster node's shorter wall.**
   `estimate_projected_total_cost` (`scripts/recommend_cluster_specs.py:1007-1088`)
   prices EC2 (on-demand driver + spot workers) and DBU over a projected wall
   from `_shape_wall_minutes`, which scales by **core count** only
   (`rec_total_cores`) and disk bandwidth. There is no per-generation throughput
   term, so two same-vCPU candidates from different generations are modeled with
   the same wall — the engine cannot see that a Graviton3 node shortens the run.

4. **Presets are Gen 6.** The Databricks `consolidation_*` presets in
   `packages/bietlejuice-core/src/bietlejuice/config/prod_conf.yml` (start line
   **2185**, e.g. `consolidation_xs_compute_cluster` →
   `driver_node_type_id: c6g.large`, `node_type_id: c6g.large`) are Gen 6.
   The EMR `emr_7_12_consolidation_*` block (start line **1975**) is already
   Gen 7 (c7g/m7g/r7g) — the migration target and an existing precedent.

5. **The instance catalog has no Gen 8 at all.** `scripts/instance_catalog_data.py`
   (generated) carries Gen 6 and Gen 7 ARM only. Prices originate in
   `dags/platform/enrich_databricks_pricing/queries/enrich/dim_ec2_price.sql`;
   specs in `scripts/instance_specs.yml`; the two are joined by
   `scripts/generate_instance_catalog.py`. Targeting Gen 8 requires seeding
   both sources first.

---

## 2. Design decisions (pre-made — not open questions)

### D1. Target generation is configurable; default **Gen 7**

Add `--target-generation {6,7,8}` (default **7**) plus an optional per-family
override (`--target-generation-compute`, `--target-generation-general`,
`--target-generation-memory`, each defaulting to the global value). Replace the
hardcoded `prefix_by_family` in `_node_for_family_tier` with a
generation-parameterized builder:

```python
_FAMILY_BASE = {"compute": "c", "general": "m", "memory": "r"}

def _node_for_family_tier(family: str, tier: str, generation: int = 7) -> str:
    return f"{_FAMILY_BASE[family]}{generation}g.{_TIER_TO_SIZE[tier]}"
```

`generation` is threaded from the parsed args through the call chain (it has a
single call site today; see §3). Default 7 makes the tool emit Gen 7 shapes
out of the box; `--target-generation 6` reproduces today's behavior exactly
(regression anchor for tests).

### D2. Throughput-aware cost engine

Add a per-instance **relative throughput factor** keyed by family+generation,
normalized so Gen 6 = 1.0 within each family. Seed it from the same
Spark-calibrated speedups the analysis uses (do **not** invent new numbers):

```python
# Real-Spark per-generation speedup, normalized to Gen 6 = 1.0, per family.
# Source: AWS TPC-DS Data-on-EKS R-series (r6g→r7g 1.14×, r7g→r8g 1.085×);
# AWS EMR Spark C7g +13–19%; SPECint2017 per-core ~+12%/gen. Mid-band values.
_GEN_THROUGHPUT = {
    "compute": {6: 1.00, 7: 1.15, 8: 1.24},
    "general": {6: 1.00, 7: 1.15, 8: 1.24},
    "memory":  {6: 1.00, 7: 1.15, 8: 1.24},
}

def _node_throughput(node_type: str) -> float:
    spec = INSTANCE_CATALOG.get(node_type)
    gen = _generation_of(node_type)        # regex on the prefix; see §3
    if spec is None or gen is None:
        return 1.0
    return _GEN_THROUGHPUT.get(spec.family, {}).get(gen, 1.0)
```

In `estimate_projected_total_cost` (`:1007-1088`), divide the projected wall by
the throughput ratio between the **recommended** node mix and the **observed**
node mix before pricing — so a faster generation shortens the wall that both the
EC2 term and the DBU term are charged over:

```python
obs_throughput = _node_throughput(_worker_node_type(m) or m.driver_node_type)
rec_throughput = _node_throughput(rec_worker_type or rec_driver)
speedup = rec_throughput / obs_throughput if obs_throughput else 1.0
wall_minutes = (base_wall * (_PHOTON_OFF_WALL_INFLATION if photon_off else 1.0)) / speedup
```

`wall_h = wall_minutes / 60.0` then flows unchanged into both `ec2` (driver +
spot workers × wall) and the fleet-rate DBU term (`sum(fleet_rates) * wall_h *
_USD_PER_DBU`). Keep the change confined to the wall computation so the existing
keep-Photon / drop-Photon branches and the legacy DBU fallback are untouched.
When generations match (`speedup == 1.0`), the result is byte-identical to today.

Mirror the same `/ speedup` term in `_projected_wall_for_sla` (algorithm doc
"SLA Guard", `scripts/recommend_cluster_specs.py` `_projected_wall_for_sla`) so a
faster node that finishes sooner is not falsely blocked by the cadence SLA.

### D3. Sizing comparator → `$/hr ÷ throughput` (cost-of-work, not sticker price)

Change the sort/min keys so the selector prefers the node that does the work
cheapest, not the one with the lowest hourly rate:

- `_single_node_candidates` (`:631-642`): sort key
  `(price / _node_throughput(node_type), spec.memory_gb, spec.vcpus)`.
- `_node_for_demand` (`:704-727`): `min(..., key=lambda item: (item[2] /
  _node_throughput(item[0]), item[1].memory_gb, item[1].vcpus))`.

At ~6% more `$/hr` for ~15% more throughput, Gen 7 wins the cost-of-work
comparison; at ~10% more for ~8%, Gen 8 generally loses except where its
throughput edge is largest (`c8g`), which is the intended selective behavior.
The candidate **pool** is still filtered to the target generation by D1's
builder for preset-tier shapes; D3 governs the open `_node_for_demand` search so
it does not silently fall back to a cheaper older generation.

### D4. Seed Gen 7 (and optionally Gen 8) into the catalog

The catalog is generated, so seed the two sources then regenerate — never edit
`instance_catalog_data.py` by hand:

1. **Prices** — add Gen 7 (and Gen 8 if piloting) ARM rows to
   `dags/platform/enrich_databricks_pricing/queries/enrich/dim_ec2_price.sql`
   (the single price authority; spot is derived as `0.37 × on_demand`
   downstream). Gen 7 c7g/m7g/r7g rows are required; Gen 8 c8g/m8g/r8g rows are
   required only for the Gen 8 pilot.
2. **Specs** — add Gen 8 vCPU/RAM/family rows to `scripts/instance_specs.yml`
   (Gen 7 specs are already present). Gen 8 sizes mirror Gen 7 (large →
   16xlarge/24xlarge/48xlarge as applicable).
3. **Regenerate** — `uv run python scripts/generate_instance_catalog.py`, then
   commit the regenerated `scripts/instance_catalog_data.py`. The generator
   emits an entry only when both a spec and a seed price exist and warns on
   seed-only / spec-only mismatches — resolve every warning before committing.

### D5. Presets: phase 1 overrides, phase 2 promotion

The recommender is **report-only**: it writes `validation:` blocks
(minimal `custom_configurations` that differ from the recommended preset
defaults), never prod `cluster:` (runbook §"report-only"; algorithm doc
"Additive Single-Node Sizer" note that oversized single nodes emit the nearest
preset + `custom_configurations.driver_node_type_id`).

- **Phase 1 — `custom_configurations` overrides (no preset edits).** With D1
  defaulting to Gen 7, the recommender emits Gen 7 node types via
  `custom_configurations.{driver_node_type_id,node_type_id}` against the existing
  Gen 6 `consolidation_*` presets. This routes every change through the normal
  validation/Forno path with zero `prod_conf.yml` churn and gives per-DAG A/B
  evidence before any preset moves. (This reuses the exact emission mechanism
  the runbook documents in §5 "Write Validation Blocks".)
- **Phase 2 — promote the presets.** Once Gen 7 validations pass fleet-wide,
  migrate the Databricks `consolidation_*` block in `prod_conf.yml` (start line
  2185) to Gen 7 node types, mirroring the already-vetted
  `emr_7_12_consolidation_*` block (start line 1975). After promotion the
  recommender's emitted spec equals the preset default, so the now-redundant
  `custom_configurations` overrides drop out automatically (runbook:
  "Validations that resolve to prod's effective spec are not written").

### D6. The Photon × instance-family constraint is unchanged

Gen does not relax the Photon rule (algorithm doc "Photon × Instance-Family
Constraint", `:301-311`): Databricks rejects Photon on **compute-family** nodes
(core/RAM ratio too low). So:

- `c8g` (all compute, every tier) stays Photon-blocked; usable **STANDARD only**.
  Keep-Photon candidate generation must keep excluding the compute family
  (`_family_order_for_demand(exclude_compute=True)`) regardless of target
  generation, and the final `disable_photon` guard still force-drops Photon on
  any compute-family winner.
- `m8g`/`r8g` (and `m8gd`) are Databricks-supported flexible node types and may
  carry Photon. Confirm against
  `docs.databricks.com/aws/en/compute/flexible-node-type-instances` before the
  Gen 8 pilot; treat the support list as data, not a code assumption.

### D7. Driver and worker generation are **symmetric by default**

The recommender already emits independent `driver_node_type_id` and
`node_type_id` (on-demand driver + spot workers), so role-asymmetric generations
are mechanically possible — and an `m6g` driver + `m7g` workers cluster is valid
on Databricks (both are arm64/Graviton under one runtime; only ARM↔x86 mixing is
blocked).

**Decision: do NOT add a mixed-generation lever to the default path.** The
driver tracks the worker generation. Rationale (quantified in the analysis §8):

- The driver is a single small on-demand node and the wall is **worker-set**, so
  a Gen 6 driver under Gen 7 workers saves only ~6% of the driver's `$/hr` on its
  own slice — **<1% of total** for non-driver-heavy DAGs.
- A ~14%-slower Gen 6 driver lengthens any driver-bound phase (broadcast build,
  `collect`, query planning), which re-inflates worker-spot **and** DBU and can
  erase the saving.

Mixed-gen is documented **only** as an explicit, opt-in exception for amortizing
under-utilized **Gen 6 Reserved Instances / Savings Plans** (sunk capacity). If
implemented, gate it behind a separate flag (e.g.
`--driver-generation {6,7,8}`, default = `--target-generation`) so the symmetric
default is never altered silently. This flag is **out of scope** for the default
migration and ships, if at all, only when an RI burn-down is prioritized.

---

## 3. Step-by-step edits (ordered)

Each step names the file and function. Steps 1-6 are the code change; step 7 is
the catalog seed; steps 8-9 are presets and docs.

1. **Generation regex helper.** Add `_generation_of(node_type: str) -> int | None`
   near the existing `ARM_REGEX` (`scripts/recommend_cluster_specs.py:100`):
   `re.match(r'^([cmr])([0-9]+)g', node_type)` → `int(group(2))`. Used by D2/D3.
2. **Throughput table + accessor.** Add `_GEN_THROUGHPUT` and `_node_throughput`
   (D2) next to the other module constants (near `_SPOT_TO_ON_DEMAND_RATIO`,
   `:138`).
3. **Generation-parameterized builder.** Rewrite `_node_for_family_tier`
   (`:600-602`) per D1; add the module-level `_FAMILY_BASE` map. Update its
   single call site to pass the resolved target generation for that family.
4. **Cost-of-work comparators.** Apply D3 to the sort key in
   `_single_node_candidates` (`:640-642`) and the `min` key in `_node_for_demand`
   (`:723-726`).
5. **Throughput-aware wall.** Apply D2's `/ speedup` term in
   `estimate_projected_total_cost` (`:1056-1058`, the `wall_minutes`
   computation) and the mirror in `_projected_wall_for_sla`.
6. **CLI wiring.** Add `--target-generation` (+ per-family overrides) to the
   `argparse` setup in `main()` and thread the resolved per-family generation
   through `build_recommendation` → the sizer/refined-multi levers → the builder
   in step 3. Echo the chosen generation(s) in `--list` output and as a column in
   `recommendations.csv` (`target_generation`) for auditability — extend
   `_CSV_FIELDS` (`:4144-4215`) accordingly.
7. **Catalog seed + regenerate.** Execute D4 (prices in `dim_ec2_price.sql`,
   Gen 8 specs in `instance_specs.yml`, `generate_instance_catalog.py`, commit
   `instance_catalog_data.py`). Resolve all generator warnings.
8. **Presets.** Execute D5 phase 1 first (no `prod_conf.yml` edit; overrides
   emitted by the tool). Defer phase 2 (promote `consolidation_*` to Gen 7 in
   `prod_conf.yml`) until validations pass.
9. **Docs.** Update `cluster_spec_recommender_algorithm.md` ("Instance Catalog",
   "Cost Engine") and `cluster_spec_recommender_runbook.md` (new flag in the
   flags table) to describe the target-generation flag and the throughput term.

---

## 4. New unit tests

Add to `tests/unit/scripts/test_recommend_cluster_specs.py` (stdlib + existing
fixtures; no Trino/network):

- **Target-generation selection.** `_node_for_family_tier("compute", "m",
  generation=7)` → `c7g.<size>`; `generation=8` → `c8g.<size>`; `generation=6`
  reproduces the legacy `c6g.<size>` (regression guard).
- **Generation parser.** `_generation_of` maps `m6g.2xlarge`→6, `r7gd.4xlarge`→7,
  `c8g.xlarge`→8, and returns `None` for an x86 node.
- **Throughput-aware cost beats cheaper-but-slower.** With a catalog containing a
  same-vCPU Gen 6 and Gen 7 node, assert `estimate_projected_total_cost` for the
  Gen 7 shape is lower than the Gen 6 shape on a workload whose wall is long
  enough that the ~15% wall cut outweighs the ~6% `$/hr` bump — and that the
  Gen 7 node is the one `_node_for_demand` returns under D3.
- **Generation-neutral regression.** With `--target-generation 6`, a fixed DAG
  fixture produces the *same* recommended preset/nodes and the same
  `est_cost_per_run_usd` as the pre-change baseline (lock D1/D2/D3 to no-ops when
  gen matches).
- **Driver tracks worker generation.** A recommendation emitted at
  `--target-generation 7` has `rec_driver_node_type` and `rec_worker_node_type`
  on the **same** generation (no implicit mixed-gen).
- **Photon × compute stays blocked.** A keep-Photon candidate never lands on a
  `c7g`/`c8g` node; a compute-family winner is force-dropped to STANDARD
  regardless of target generation.

---

## 5. Mandatory gates (from the runbook / AGENTS.md)

Run before opening the PR (these are the recommender's standing gates plus the
repo governance checks; see `cluster_spec_recommender_runbook.md` §6 and
`AGENTS.md`):

```bash
uv run pytest tests/unit/scripts/test_recommend_cluster_specs.py
make check-style
uv run python scripts/generate_instance_catalog.py   # catalog regenerated + committed
# Live smoke (needs VPN + Trino OAuth):
uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py --trino --list --target-generation 7
make validate-cluster-validation-files
make create-dag-files
```

Then the standard governance batch on any DAG/cluster YAML touched in phase 2
(`make validate-metadata-files-*`, `make dependencies-file`, etc.) and a **Forno
run before merge** per AGENTS.md. No promotion happens from the report — every
changed spec needs a validation DAG run (runbook §4).

---

## 6. Risks & rollout

- **Spot availability / volatility.** Gen 7/8 spot pools are shallower than Gen 6
  in some AZs; a validation run that cannot get spot capacity will fall back or
  fail. Watch the validation outcomes (`--validation-outcomes`) for capacity
  errors before promoting.
- **Per-generation DBU rate drift.** D2 assumes DBU/node-hour is generation-
  neutral at matched vCPU/RAM. Verify against `_FLEET_DBU_RATE` (loaded from
  non-Photon homogeneous-cluster telemetry); if a generation shows >~5% drift at
  equal size, price DBU with the actual per-type rate instead of the neutral
  assumption.
- **Phased rollout.** Gen 7 fleet-wide (default); Gen 8 **pilot on `c8g`** /
  per-core-bound / Java-heavy DAGs only (`--target-generation-compute 8`), never
  fleet-wide — its ~10% price bump ≈ its ~8% Spark speedup for memory/general.
- **A/B safety net.** Reuse the existing `__validation` outcome comparison
  (`--validation-outcomes`, runbook §3b) to confirm projected vs observed cost
  and wall on the new generation before each promotion. Keep the post-promotion
  watch (`promote_rightsizing_validations.py --watch`) for revert evidence.
- **Regression containment.** D1/D2/D3 are guarded to be exact no-ops when the
  target generation equals the observed generation, so a `--target-generation 6`
  run is provably identical to today's output — the safe rollback switch.
