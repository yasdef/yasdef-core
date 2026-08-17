from __future__ import annotations

_CLASS_ALIASES: dict[str, tuple[str, ...]] = {
    "back": ("back", "backend", "api", "server"),
    "front": ("front", "frontend", "front-end", "web", "ui"),
    "mobile": ("mobile", "ios", "android", "react-native"),
}

_CLASS_SUBSTRINGS: dict[str, tuple[str, ...]] = {
    "back": ("back", "backend"),
    "front": ("front", "frontend", "web"),
    "mobile": ("mobile", "ios", "android"),
}


def normalize_worker_class(raw: str) -> str:
    """Map a raw binding class value to back/front/mobile, or '' when unsupported."""
    value = raw.strip().lower()
    for normalized, aliases in _CLASS_ALIASES.items():
        if value in aliases:
            return normalized
    return ""


def filename_matches_class(normalized: str, filename: str) -> bool:
    """Class-substring partition rule shared with the design discovery helper."""
    name = filename.lower()
    return any(token in name for token in _CLASS_SUBSTRINGS.get(normalized, ()))
