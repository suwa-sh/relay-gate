#!/usr/bin/env python3
"""テスト fixture 生成器: rdb-schema.yaml から PostgreSQL の DDL(facade/test/fixtures/relay-gate-db.postgresql.sql)を生成する。

- 正本は docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml と worker/migrations(datastore_owner: tier-worker)。
  本生成物は tier-facade の実 PostgreSQL テストが使う fixture であり、本番 migration ではない
- 対象は UC 6078c4ed が操作するテーブルのみ(rdb-schema.yaml transaction_rules「slot起動トランザクション」の tables)
- 型対応: uuid → uuid / string → text / text → text / integer → integer / datetime → timestamptz
- 開発時のみ使う(PyYAML が必要)。CI・テスト実行時には呼ばない

使い方: python3 facade/test/fixtures/generate-postgresql-schema.py
"""

from __future__ import annotations

import pathlib
import sys

import yaml

REPO_ROOT = pathlib.Path(__file__).resolve().parents[3]
SCHEMA_PATH = REPO_ROOT / "docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml"
OUTPUT_PATH = pathlib.Path(__file__).resolve().parent / "relay-gate-db.postgresql.sql"
TRANSACTION_RULE = "slot起動トランザクション"
TYPE_MAP = {"uuid": "uuid", "string": "text", "text": "text", "integer": "integer", "datetime": "timestamptz"}


def column_ddl(column: dict) -> str:
    sql_type = TYPE_MAP[column["type"]]
    nullability = "" if column.get("nullable", True) else " NOT NULL"
    return f"  {column['name']} {sql_type}{nullability}"


def table_ddl(table: dict, known_tables: set[str]) -> list[str]:
    lines = [column_ddl(column) for column in table["columns"]]
    lines.append(f"  PRIMARY KEY ({', '.join(table['primary_key'])})")
    for index in table.get("indexes", []):
        if index.get("unique"):
            lines.append(f"  CONSTRAINT {index['name']} UNIQUE ({', '.join(index['columns'])})")
    for foreign_key in table.get("foreign_keys", []):
        reference = foreign_key["references"]
        if reference["table"] not in known_tables:
            continue
        on_delete = f" ON DELETE {foreign_key['on_delete']}" if foreign_key.get("on_delete") else ""
        lines.append(
            f"  FOREIGN KEY ({', '.join(foreign_key['columns'])}) REFERENCES {reference['table']} ({', '.join(reference['columns'])}){on_delete}"
        )
    statements = [f"CREATE TABLE {table['name']} (\n" + ",\n".join(lines) + "\n);"]
    for index in table.get("indexes", []):
        if not index.get("unique"):
            statements.append(f"CREATE INDEX {index['name']} ON {table['name']} ({', '.join(index['columns'])});")
    return statements


def main() -> int:
    schema = yaml.safe_load(SCHEMA_PATH.read_text(encoding="utf-8"))
    rule = next(rule for rule in schema["transaction_rules"] if rule["name"] == TRANSACTION_RULE)
    target_names = list(rule["tables"])
    tables_by_name = {table["name"]: table for table in schema["tables"]}
    header = [
        "-- テスト fixture。正本は rdb-schema.yaml / worker/migrations(datastore_owner: tier-worker)。",
        f"-- facade/test/fixtures/generate-postgresql-schema.py が rdb-schema.yaml(version {schema['version']})の",
        f"-- transaction_rules「{TRANSACTION_RULE}」の tables から生成した。手動編集せず、正本の変更時に再生成する。",
        "",
    ]
    statements: list[str] = []
    for name in target_names:
        statements.extend(table_ddl(tables_by_name[name], set(target_names)))
    OUTPUT_PATH.write_text("\n".join(header) + "\n" + "\n\n".join(statements) + "\n", encoding="utf-8")
    print(f"generated {OUTPUT_PATH.relative_to(REPO_ROOT)} ({len(target_names)} tables)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
