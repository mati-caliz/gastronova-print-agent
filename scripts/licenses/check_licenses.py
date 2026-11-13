"""Compara las licencias de las dependencias de producción con la lista común del estándar.

Lee de la entrada estándar pares `paquete<TAB>licencia` (uno por línea), los que arma cada
`verify-licenses` a partir de la herramienta de su pila, y frena si alguno no está permitido.
Una expresión SPDX con OR pasa si alguna alternativa está permitida; con AND, si lo están todas.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

LICENSES_FILE = Path(__file__).with_name("licenses.json")
TOKEN = re.compile(r"\(|\)|\bAND\b|\bOR\b|[^\s()]+(?:\s+WITH\s+[^\s()]+)?")
OR_OPERATOR = "OR"
AND_OPERATOR = "AND"


def tokens_of(expression: str) -> list[str]:
    return TOKEN.findall(expression.strip())


def evaluate(tokens: list[str], allowed: set[str]) -> bool:
    position = 0

    def alternatives() -> bool:
        nonlocal position
        result = requirements()
        while position < len(tokens) and tokens[position] == OR_OPERATOR:
            position += 1
            result = requirements() or result
        return result

    def requirements() -> bool:
        nonlocal position
        result = term()
        while position < len(tokens) and tokens[position] == AND_OPERATOR:
            position += 1
            result = term() and result
        return result

    def term() -> bool:
        nonlocal position
        symbol = tokens[position]
        position += 1
        if symbol == "(":
            result = alternatives()
            position += 1
            return result
        return symbol in allowed

    if not tokens:
        return False
    result = alternatives()
    return result and position == len(tokens)


def is_exception(package: str, exceptions: set[str]) -> bool:
    """Una excepción de un módulo de Go cubre sus subpaquetes: go-licenses reporta por paquete."""
    return any(package == name or package.startswith(f"{name}/") for name in exceptions)


def main() -> int:
    policy = json.loads(LICENSES_FILE.read_text(encoding="utf-8"))
    allowed = set(policy["allowed"])
    exceptions = set(policy["packages"])
    rejected: list[str] = []
    for line in sys.stdin:
        package, _, expression = line.rstrip("\n").partition("\t")
        if not package or is_exception(package, exceptions):
            continue
        if not evaluate(tokens_of(expression), allowed):
            rejected.append(f"{package}: {expression or 'sin licencia declarada'}")
    for entry in sorted(set(rejected)):
        sys.stderr.write(f"licencia no permitida · {entry}\n")
    return 1 if rejected else 0


if __name__ == "__main__":
    raise SystemExit(main())
