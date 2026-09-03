# `allocation_tool` — S3 ingestion reference

| Field | Value |
| --- | --- |
| **Tables** | `datalake_allocation_tool_raw.{allocation,delta,tags,groups}` (one per export prefix) → `datalake_allocation_tool_clean.{allocations,tags,groups}` → `datalake_people.allocation_history` → `dw_workforce_allocation.fact_workforce_allocations` |
| **Business owner** | Enterprise Engineering (PgM org) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Feed of the Base44 Allocation Tool: user-defined groups and tags, and the employee-to-tag allocations that produce FTE splits across BUs, projects and initiatives. |
| **Business purpose** | Resource allocation lived in spreadsheets (Team Formation), which drifts and does not scale to ad-hoc, one-off groupings. The Allocation Tool lets ET, the PgM org and HRBPs define their own groups and tags and link employees to them, so quarterly planning scenarios can be simulated quickly. |
| **Business consumer** | TARS, Superset, and ad-hoc reports (Google Sheets). |
| **Source of truth** | The Base44 app is the source of truth for groups, tags and allocations. Employee records inside the tool are **read-only**, seeded from PIN via S3 (D-1). The sync is one-directional: PIN → S3 → tool. The tool never writes back to PIN. |
| **Delivery channel** | `s3://5a-base44-office/allocationtool/export/`, with `allocation/`, `tags/`, `groups/` and `delta/` prefixes. `allocationtool/import/` is the inbound side (PIN data the app reads) and is not ingested. |
| **Refresh** | **Full snapshot on every export.** See below — this changed, and the delta mechanism is effectively retired. |
| **Status** | **Prototype.** Production rollout is a separate decision after validation, so treat the schema as unstable and expect the export contract to change. |

Source: [PRD — Allocation Tool](https://quintoandar.atlassian.net/browse/DBP-1856). Ingestion DAG: `bietlejuice.s3_ingestion`.

## The export contract changed to snapshot-only

The original contract was snapshot-then-deltas: one initial full dump, then incremental
documents carrying only what changed since a `watermark`. **That is no longer what
happens.** As of 2026-09-02 the bucket holds a single delta file, from 2026-08-24, and
everything since is a full `allocations-snapshot-*` dump.

This is not a cosmetic difference — it decides how the layers above are modelled:

- **Repeated states.** Every export repeats all ~940 allocations, changed or not, so the
  history must open a new version only when an attribute actually changed. Otherwise it
  degenerates into one row per allocation per day.
- **Deletion becomes detectable.** An allocation absent from a *snapshot* no longer
  exists at the source. Absence from a *delta* means nothing. `allocations.export_type`
  records which kind produced each row, so downstream can tell the two apart;
  `allocation_history.is_removed_at_source` is the result.

## Export shapes

Three shapes are in the bucket, and they are not interchangeable:

1. **Bare array** — the initial dumps of 2026-08-19. The file *is* a JSON array of
   records, with no envelope and therefore no `generated_at`.
2. **Delta envelope** — `delta/`, one file, 2026-08-24:
   `{ "watermark", "generated_at", "counts", "allocations": [...], "tags": [...], "groups": [...] }`
3. **Snapshot envelope** — `allocation/allocations-snapshot-*`, current:
   `{ "count", "entity", "type", "generated_at", "records": [...] }`

The clean query discriminates on the presence of the key, not on the leading character:
`$.records` for the snapshot envelope, `$.allocations` for the delta envelope. A
`COALESCE` between the two cannot work — Spark parses an object as `ARRAY<...>` into a
one-element array of nulls rather than returning `NULL`, so the second branch would
never run and its records would be dropped silently.

> **Known gap:** the bare-array dumps of 2026-08-19 carry no `records` key and are
> therefore *not* ingested. History starts at the first snapshot envelope, not at the
> first export. Recovering them needs a third branch in the clean query.

## `id_employee` is not stable

The app reissues its internal employee id whenever it re-seeds employees from PIN. On
2026-08-27 all 938 existing allocations got a new `id_employee` while every other field
stayed byte-identical. `id_allocation`, `id_tag` and `id_group` did stay stable across
that rewrite.

Since that re-seed the column holds PIN `person_number` values — measured in September
2026, when 938 of 943 allocations resolved through `identifier_mapping.person_number`
and every one of them agreed with the `employee_name` the export itself carries. That is
a description of today's data, **not a guarantee**: the next re-seed can change it
again. So `allocation_history` resolves people through it but guards the result with a
data-quality check that fails if resolution drops below 90%, and the SCD2 fingerprint
deliberately excludes `id_employee` — otherwise a bulk re-seed would look like every
employee changing allocation on the same day.

## Entity model

| Entity | Definition | Cardinality |
| --- | --- | --- |
| **Group** (tag class) | User-defined category — e.g. `BU`. Names are unique **globally**. | Holds 1-N tags |
| **Tag** | Belongs to exactly one group — e.g. `ForSale` under group `BU`. Names are unique **only within their own group**, so a tag is identified by the pair (group, tag), never by name alone. | Belongs to 1 group |
| **Employee** | Read-only, seeded from PIN. | — |
| **Allocation** | The link between an employee and a tag, from which FTE is derived. | An employee holds 0-N tags **per group** |

A `PIN` tag class is reserved as read-only, so PIN-owned data has a place in the model
without being editable in the tool.

## Rules that shape the data

1. **FTE splits evenly (1/N)** across the N tags an employee holds within the same
   group. Only equal splits exist — arbitrary percentages are explicitly out of scope,
   so any weight other than `1/N` means the export contract changed.
2. **An employee can hold 0 tags in a group.** They contribute no row for that group, so
   FTE sums to 1 only for employees holding at least one tag in it. Do not assume every
   employee appears under every group. It also follows that FTE is **not additive across
   groups**: someone allocated in two groups contributes 1.0 in each.
3. **Deletion is soft** in the app: groups, tags and allocations are marked inactive
   rather than removed, so deactivation arrives as a new version. Since the switch to
   snapshots, a record can *also* vanish outright, which the history reads as removal.
4. **History is retained in the Datalake.** The tool itself only shows current state.
5. **No guardrails against overlap with PIN classifications** (vertical team, horizontal
   team). A tag may duplicate or contradict a PIN-owned attribute, and nothing validates
   that.

## Reading the tables

The three clean tables do **not** share a grain:

| Table | Grain | How to read current state |
| --- | --- | --- |
| `allocations` | one row per allocation **and version** | latest `ts_version` per `id_allocation` |
| `tags` | one row per tag (MERGEd) | read it directly |
| `groups` | one row per group (MERGEd) | read it directly |

So `allocations` is a changelog and the other two are current state. Counting rows in
`allocations` counts versions, not allocations.

For anything time-related, prefer `datalake_people.allocation_history`: it collapses the
version log into non-overlapping validity intervals, so point-in-time is a `BETWEEN`
rather than a window function.

```sql
-- current state, from the clean changelog
SELECT id_allocation, tag_name, status
FROM (
    SELECT a.*, ROW_NUMBER() OVER (
        PARTITION BY id_allocation ORDER BY ts_version DESC
    ) AS rn
    FROM datalake_allocation_tool_clean.allocations AS a
)
WHERE rn = 1 AND NOT COALESCE(is_sample, FALSE)

-- the same question, one layer up
SELECT id_allocation, tag_name, status
FROM datalake_people.allocation_history
WHERE is_current AND NOT COALESCE(is_sample, FALSE)
```

- **Do not filter the partition window when you want current state.** Partitions record
  when a version *arrived*, so a record last changed in August is absent from a
  September-only window. Read the full history, or the partitions up to your cut-off.
- **Partitions are the ingestion date, not `ts_version`.** The Airflow load window is
  expressed in ingestion dates, so a late or retried export lands in the partition of
  the day it was ingested even though it was generated earlier.
- **Filter `is_sample = false`** for analysis: Base44 seeds demo records.
- **Join tags on `id_tag`**, or on `(id_group, tag_name)` — never on `tag_name` alone,
  which is unique only inside its group.
- **FTE is not a column in clean.** It is `1 / N` over the N tags an employee holds in a
  group, computed in `dw_workforce_allocation.fact_workforce_allocations`.

## Timestamps

The export mixes zone-qualified values (`allocated_at`, `generated_at`) with naive ones
(`created_date`, `updated_date`), and the clean queries cast both as-is. Naive values
are therefore interpreted in the session timezone, which this repo does not pin — treat
`ts_created` and `ts_updated` as approximate and prefer `ts_version`, which is derived
from `generated_at` and falls back to the S3 modification time.
