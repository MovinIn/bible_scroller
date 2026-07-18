from __future__ import annotations

import re
from dataclasses import dataclass

_REFERENCE_PATTERN = re.compile(
    r"^(?P<book>(?:\d\s+)?[A-Za-z]+(?:\s+[A-Za-z]+)*)\s+"
    r"(?P<chapter>\d+):"
    r"(?P<start>\d+)"
    r"(?:-(?P<end>\d+))?$"
)


@dataclass(frozen=True)
class VerseReference:
    book: str
    chapter: int
    start_verse: int
    end_verse: int

    def slug(self) -> str:
        return f"{self.book.replace(' ', '_')}_{self.chapter}_{self.start_verse}-{self.end_verse}"


def parse_reference(reference: str) -> VerseReference:
    cleaned = reference.strip()
    match = _REFERENCE_PATTERN.match(cleaned)
    if not match:
        raise ValueError(f"Invalid verse reference: {reference!r}")

    start = int(match.group("start"))
    end = int(match.group("end")) if match.group("end") else start
    if end < start:
        raise ValueError(f"Invalid verse reference: {reference!r}")

    return VerseReference(
        book=match.group("book"),
        chapter=int(match.group("chapter")),
        start_verse=start,
        end_verse=end,
    )
