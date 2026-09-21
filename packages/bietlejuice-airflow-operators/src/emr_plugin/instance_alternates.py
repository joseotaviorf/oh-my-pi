#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
"""ARM-first instance type alternate mapping for EMR instance fleets.

Maps declared Graviton instance families to ordered fallback families that are
1:1 on vCPU and memory for the same size suffix: remaining Graviton generations
first (newest first), then x86 cheapest-first (6a -> 6i -> 7i -> 7a).
"""

from __future__ import annotations

import re
from typing import List, Optional

INSTANCE_ALTERNATES: dict[str, tuple[str, ...]] = {
    # Graviton -> other Graviton gens (newest first), then x86 cheapest-first.
    "c6g": ("c7g", "c6a", "c6i", "c7i", "c7a"),
    "c7g": ("c6g", "c6a", "c6i", "c7i", "c7a"),
    "c8g": ("c7g", "c6g", "c6a", "c6i", "c7i", "c7a"),
    "m6g": ("m7g", "m6a", "m6i", "m7i", "m7a"),
    "m7g": ("m6g", "m6a", "m6i", "m7i", "m7a"),
    "m8g": ("m7g", "m6g", "m6a", "m6i", "m7i", "m7a"),
    "r6g": ("r7g", "r6a", "r6i", "r7i", "r7a"),
    "r7g": ("r6g", "r6a", "r6i", "r7i", "r7a"),
    "r8g": ("r7g", "r6g", "r6a", "r6i", "r7i", "r7a"),
    # Local-NVMe: only Graviton gd and Intel 6id keep the 474 GiB/2xlarge disk.
    "c6gd": ("c7gd", "c6id"),
    "c7gd": ("c6gd", "c6id"),
    "c8gd": ("c7gd", "c6gd", "c6id"),
    "m6gd": ("m7gd", "m6id"),
    "m7gd": ("m6gd", "m6id"),
    "m8gd": ("m7gd", "m6gd", "m6id"),
    "r6gd": ("r7gd", "r6id"),
    "r7gd": ("r6gd", "r6id"),
    "r8gd": ("r7gd", "r6gd", "r6id"),
    # x86 -> remaining x86 alternates (cheapest first: 6a -> 6i -> 7i -> 7a)
    "c6a": ("c6i", "c7i", "c7a"),
    "c6i": ("c6a", "c7i", "c7a"),
    "c7i": ("c6a", "c6i", "c7a"),
    "c7a": ("c6a", "c6i", "c7i"),
    "m6a": ("m6i", "m7i", "m7a"),
    "m6i": ("m6a", "m7i", "m7a"),
    "m7i": ("m6a", "m6i", "m7a"),
    "m7a": ("m6a", "m6i", "m7i"),
    "r6a": ("r6i", "r7i", "r7a"),
    "r6i": ("r6a", "r7i", "r7a"),
    "r7i": ("r6a", "r6i", "r7a"),
    "r7a": ("r6a", "r6i", "r7i"),
}

GRAVITON_FAMILY_PATTERN = re.compile(r"^[a-z]+\d+gd?$")
INSTANCE_TYPE_PATTERN = re.compile(r"^([a-z0-9]+)\.(.+)$")
MAX_INSTANCE_TYPES_PER_FLEET = 30


def alternates(instance_type: str) -> List[str]:
    """Return ordered alternate instance types preserving the size suffix.

    Returns an empty list for unmapped families or invalid input.
    """
    if not isinstance(instance_type, str):
        return []

    normalized = instance_type.strip().lower()
    match = INSTANCE_TYPE_PATTERN.match(normalized)
    if not match:
        return []

    family, size = match.group(1), match.group(2)
    mapped_families = INSTANCE_ALTERNATES.get(family)
    if not mapped_families:
        return []

    return [f"{alt}.{size}" for alt in mapped_families]


def with_alternates(instance_types: List[str]) -> List[str]:
    """Expand declared instance types with their alternates.

    Declared types appear first in declared order, followed by each type's
    alternates in order, de-duplicated preserving first occurrence, truncated
    to MAX_INSTANCE_TYPES_PER_FLEET.
    """
    result: List[str] = []
    seen: set[str] = set()

    for itype in instance_types:
        if not isinstance(itype, str):
            continue
        normalized = itype.strip().lower()
        if normalized and normalized not in seen:
            seen.add(normalized)
            result.append(normalized)

    for itype in instance_types:
        for alt in alternates(itype):
            if alt not in seen:
                seen.add(alt)
                result.append(alt)
                if len(result) >= MAX_INSTANCE_TYPES_PER_FLEET:
                    return result[:MAX_INSTANCE_TYPES_PER_FLEET]

    return result[:MAX_INSTANCE_TYPES_PER_FLEET]


def is_graviton(instance_type: str) -> bool:
    """Return True if the instance type belongs to a Graviton family."""
    if not isinstance(instance_type, str):
        return False
    match = INSTANCE_TYPE_PATTERN.match(instance_type.strip().lower())
    if not match:
        return False
    return bool(GRAVITON_FAMILY_PATTERN.match(match.group(1)))


def first_x86(instance_type: str) -> Optional[str]:
    """Return the first x86 alternate for an instance type, or None."""
    if not is_graviton(instance_type):
        return None
    for alt in alternates(instance_type):
        match = INSTANCE_TYPE_PATTERN.match(alt)
        if match and not GRAVITON_FAMILY_PATTERN.match(match.group(1)):
            return alt
    return None
