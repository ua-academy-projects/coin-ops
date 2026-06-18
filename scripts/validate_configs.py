#!/usr/bin/env python3

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource


root = Path(__file__).resolve().parents[1]
configs = root / "configs"
schemas = configs / "schema"
schema_map = {
    "vm.json": "vm.schema.json",
    "vm-multicloud.json": "vm.schema.json",
    "test.json": "vm.schema.json",
    "k3s.json": "k3s.schema.json",
}


def load_json(path):
    return json.loads(path.read_text())


loaded = {}
registry = Registry()
for name in ["defs.json", "base.schema.json", "vm.schema.json", "k3s.schema.json"]:
    path = schemas / name
    data = load_json(path)
    data["$id"] = path.resolve().as_uri()
    loaded[name] = data
    registry = registry.with_resource(data["$id"], Resource.from_contents(data))


paths = [Path(sys.argv[1]).resolve()] if len(sys.argv) > 1 else sorted(configs.glob("*.json"))
ok = True

for path in paths:
    name = path.name
    if name not in schema_map:
        print(f"{path}: no schema")
        ok = False
        continue
    schema = loaded[schema_map[name]]
    errors = sorted(Draft202012Validator(schema, registry=registry).iter_errors(load_json(path)), key=lambda e: list(e.path))
    if not errors:
        print(f"{path}: ok")
        continue
    ok = False
    for e in errors:
        where = "$" + "".join(f"[{x}]" if isinstance(x, int) else f".{x}" for x in e.path)
        print(f"{path}:{where}: {e.message}")

sys.exit(0 if ok else 1)
