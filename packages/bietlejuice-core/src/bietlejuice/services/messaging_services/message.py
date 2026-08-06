from dataclasses import dataclass
from typing import Optional


@dataclass
class Message:
    content: str
    destination: str
    thread_key: Optional[str] = None
