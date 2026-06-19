"""Persist last-processed document versions to avoid redundant sync runs."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


class SyncStateStore:
    """JSON file tracking document URN → content hash / last sync timestamp."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self._state: dict[str, Any] = {}
        self._load()

    def _load(self) -> None:
        if self.path.is_file():
            with self.path.open(encoding="utf-8") as fh:
                self._state = json.load(fh)
        else:
            self._state = {"documents": {}}

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("w", encoding="utf-8") as fh:
            json.dump(self._state, fh, indent=2, sort_keys=True)

    def content_hash(self, document_urn: str) -> str:
        return str(
            (self._state.get("documents") or {}).get(document_urn, {}).get("hash", "")
        )

    def mark_synced(
        self,
        document_urn: str,
        content_hash: str,
        *,
        data_product_id: str,
        delivery_mode: str,
        pr_url: str = "",
    ) -> None:
        docs = self._state.setdefault("documents", {})
        docs[document_urn] = {
            "hash": content_hash,
            "data_product_id": data_product_id,
            "delivery_mode": delivery_mode,
            "pr_url": pr_url,
        }
        self.save()

    def is_unchanged(self, document_urn: str, content_hash: str) -> bool:
        return self.content_hash(document_urn) == content_hash
