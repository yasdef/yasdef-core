from __future__ import annotations

from importlib import resources

from .layout import RuntimeLayout


class TemplateLoader:
    def __init__(self, layout: RuntimeLayout, *, package: str = "yasdef_worker.templates.prompts"):
        self.layout = layout
        self.package = package

    def load(self, name: str) -> str:
        filename = f"{name}.md"
        override = self.layout.templates_dir / "prompts" / filename
        if override.exists():
            return override.read_text(encoding="utf-8")
        return resources.files(self.package).joinpath(filename).read_text(encoding="utf-8")
