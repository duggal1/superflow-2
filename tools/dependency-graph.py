#!/usr/bin/env python3
"""Generate a Mermaid graph from local SwiftPM package dependencies."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MANIFESTS = (ROOT / "Packages", ROOT / "App", ROOT / "tools" / "Superflowctl")
PACKAGE_PATH = re.compile(r'\.package\(path:\s*"([^"]+)"')
# SwiftPM checkouts under `.build` contain third-party manifests (FluidAudio
# ships its own examples) that are not part of this repository's layering.
EXCLUDED_PARTS = {".build", ".git", ".swiftpm", "checkouts", "artifacts", "SourcePackages"}


def is_local_manifest(path: Path) -> bool:
    return not EXCLUDED_PARTS.intersection(path.relative_to(ROOT).parts)


def layer_for(relative_path: str) -> str:
    if relative_path.startswith("Packages/L0-Core/"):
        return "L0 Core"
    if relative_path.startswith("Packages/L1-Adapters/"):
        return "L1 Adapters"
    if relative_path.startswith("Packages/L2-Engines/"):
        return "L2 Engines"
    if relative_path.startswith("Packages/L3-Features/"):
        return "L3 Features"
    if relative_path.startswith("Packages/L4-UI/"):
        return "L4 UI"
    if relative_path.startswith("App/"):
        return "L5 App"
    return "L5 Tools"


def node_id(relative_path: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", relative_path)


def generate() -> str:
    manifests = sorted(
        path for base in MANIFESTS for path in base.rglob("Package.swift")
        if is_local_manifest(path)
    )
    packages = {manifest.parent.resolve(): manifest for manifest in manifests}
    nodes: dict[str, tuple[str, str]] = {}
    edges: set[tuple[str, str]] = set()

    for directory, manifest in packages.items():
        relative = directory.relative_to(ROOT).as_posix()
        identifier = node_id(relative)
        nodes[identifier] = (layer_for(relative), directory.name)
        source = manifest.read_text(encoding="utf-8")
        for dependency_path in PACKAGE_PATH.findall(source):
            dependency = (directory / dependency_path).resolve()
            if dependency in packages:
                edges.add((identifier, node_id(dependency.relative_to(ROOT).as_posix())))

    lines = ["flowchart TB"]
    groups: dict[str, list[tuple[str, str]]] = {}
    for identifier, (layer, label) in nodes.items():
        groups.setdefault(layer, []).append((identifier, label))
    for layer, members in groups.items():
        group_id = node_id(layer)
        lines.append(f'  subgraph {group_id}["{layer}"]')
        for identifier, label in sorted(members):
            lines.append(f'    {identifier}["{label}"]')
        lines.append("  end")
    for owner, dependency in sorted(edges):
        lines.append(f"  {owner} --> {dependency}")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="write graph to this path; stdout if omitted")
    args = parser.parse_args()
    graph = generate()
    if args.output:
        output = args.output if args.output.is_absolute() else ROOT / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(graph, encoding="utf-8")
    else:
        print(graph, end="")


if __name__ == "__main__":
    main()
