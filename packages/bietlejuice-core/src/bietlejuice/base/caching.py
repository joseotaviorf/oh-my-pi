"""Sizing for the process-scoped, parse-time LRU caches.

One knob for every cache the dag-processor fills while building DAGs: the
declaration/cluster parse cache, the DAG path lookup, the per-layer query /
data-quality / metadata path listings, and the DAG doc reader.

Sized for ~1200 DAGs (bi-etl-ejuice plus the quintoml-sourced bundles):

* The per-(dag, layer) listings hold one entry per layer a DAG actually
  touches, typically one or two of ``LayerEnum``'s twelve values.
* The declaration cache is keyed by content digest, so a deploy adds a second
  generation of entries for every changed DAG rather than replacing the old
  ones. 8192 leaves room for several generations before eviction starts
  dropping still-live entries.

``lru_cache`` allocates entries lazily, so raising the cap costs nothing until
they are populated. Measured over 811 declarations, a parsed declaration
averages ~5 KiB, so one full generation is ~6 MiB and a saturated
8192-entry cache is ~39 MiB.
"""

PARSE_CACHE_MAXSIZE = 8192
