"""Las licencias de las dependencias de producción de un paquete Python, como `nombre<TAB>licencia`.

Recibe la salida de `uv export --no-dev` y le pregunta a PyPI la licencia de cada versión, sin
instalar nada: así se revisa también lo que sólo viaja en la imagen. La respuesta de cada
versión se guarda en una caché local, porque una versión publicada no cambia.
La licencia sale de `license_expression` (PEP 639), del clasificador o del campo `license`.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

CACHE_DIRECTORY = Path.home() / ".cache" / "quality-licenses" / "pypi"
PYPI_URL = "https://pypi.org/pypi/{name}/{version}/json"
REQUEST_TIMEOUT_SECONDS = 20
REQUIREMENT = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)(?:\[[^\]]*\])?==([^\s;]+)")
CLASSIFIER_PREFIX = "License :: OSI Approved :: "
CLASSIFIER_LICENSES = {
    "Apache Software License": "Apache-2.0",
    "BSD License": "BSD-3-Clause",
    "ISC License (ISCL)": "ISC",
    "MIT License": "MIT",
    "MIT No Attribution License (MIT-0)": "MIT-0",
    "Mozilla Public License 2.0 (MPL 2.0)": "MPL-2.0",
    "Python Software Foundation License": "PSF-2.0",
    "The Unlicense (Unlicense)": "Unlicense",
    "zlib/libpng License": "Zlib",
}
# El campo `license` viejo es texto libre: estos nombres se traducen a SPDX y el resto viaja tal
# cual, así el aviso muestra lo que declaró el paquete.
DECLARED_LICENSES = {
    "BSD": "BSD-3-Clause",
    "BSD License": "BSD-3-Clause",
    "MIT License": "MIT",
    "Apache 2.0": "Apache-2.0",
    "Apache License 2.0": "Apache-2.0",
    "Apache Software License": "Apache-2.0",
}


def requirements_of(export: str) -> list[tuple[str, str]]:
    found = []
    for line in export.splitlines():
        match = REQUIREMENT.match(line.strip())
        if match:
            found.append((match.group(1).lower(), match.group(2)))
    return found


def release_info(name: str, version: str) -> dict[str, object]:
    cached = CACHE_DIRECTORY / f"{name}-{version}.json"
    if cached.exists():
        info: dict[str, object] = json.loads(cached.read_text(encoding="utf-8"))
        return info
    url = PYPI_URL.format(name=name, version=version)
    with urllib.request.urlopen(url, timeout=REQUEST_TIMEOUT_SECONDS) as response:  # noqa: S310 - URL fija de PyPI
        info = json.loads(response.read())["info"]
    CACHE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    kept = {key: info.get(key) for key in ("license_expression", "license", "classifiers")}
    cached.write_text(json.dumps(kept), encoding="utf-8")
    return kept


def license_of(info: dict[str, object]) -> str:
    expression = info.get("license_expression")
    if isinstance(expression, str) and expression:
        return expression
    classifiers = info.get("classifiers")
    known = sorted(
        {
            CLASSIFIER_LICENSES[label]
            for classifier in (classifiers if isinstance(classifiers, list) else [])
            if (label := str(classifier).removeprefix(CLASSIFIER_PREFIX)) in CLASSIFIER_LICENSES
        }
    )
    if known:
        return " OR ".join(known)
    declared = str(info.get("license") or "").strip()
    return DECLARED_LICENSES.get(declared, declared.splitlines()[0] if declared else "")


def main() -> int:
    for name, version in requirements_of(sys.stdin.read()):
        sys.stdout.write(f"{name}\t{license_of(release_info(name, version))}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
