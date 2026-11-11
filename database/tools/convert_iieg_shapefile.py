#!/usr/bin/env python3
"""Convert selected Jalisco municipal polygons from IIEG SHP/DBF to PostGIS SQL.

Uses only the Python standard library. Source shapefile CRS is EPSG:6368.
"""
from __future__ import annotations

import argparse
import pathlib
import struct

TARGETS = {
    "14070": "El Salto",
    "14039": "Guadalajara",
    "14044": "Ixtlahuacán de los Membrillos",
    "14051": "Juanacatlán",
    "14098": "San Pedro Tlaquepaque",
    "14097": "Tlajomulco de Zúñiga",
    "14101": "Tonalá",
    "14120": "Zapopan",
    "14124": "Zapotlanejo",
}


def read_dbf(path: pathlib.Path) -> list[dict[str, str]]:
    data = path.read_bytes()
    count = struct.unpack_from("<I", data, 4)[0]
    header_len, record_len = struct.unpack_from("<HH", data, 8)
    fields = []
    pos = 32
    while data[pos] != 13:
        desc = data[pos : pos + 32]
        fields.append((desc[:11].split(b"\0")[0].decode("ascii"), desc[16]))
        pos += 32
    rows = []
    for i in range(count):
        record = data[header_len + i * record_len : header_len + (i + 1) * record_len]
        if record[0:1] == b"*":
            rows.append({})
            continue
        cursor, row = 1, {}
        for name, width in fields:
            row[name] = record[cursor : cursor + width].decode("utf-8").strip()
            cursor += width
        rows.append(row)
    return rows


def signed_area(ring: list[tuple[float, float]]) -> float:
    return sum(
        ring[i][0] * ring[(i + 1) % len(ring)][1]
        - ring[(i + 1) % len(ring)][0] * ring[i][1]
        for i in range(len(ring))
    ) / 2


def contains_point(ring: list[tuple[float, float]], point: tuple[float, float]) -> bool:
    x, y = point
    inside = False
    j = len(ring) - 1
    for i, (xi, yi) in enumerate(ring):
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def read_shapes(path: pathlib.Path) -> list[list[list[tuple[float, float]]]]:
    data = path.read_bytes()
    result = []
    offset = 100
    while offset < len(data):
        content_words = struct.unpack_from(">I", data, offset + 4)[0]
        body_start, body_end = offset + 8, offset + 8 + content_words * 2
        body = data[body_start:body_end]
        shape_type = struct.unpack_from("<I", body, 0)[0]
        if shape_type == 0:
            result.append([])
        elif shape_type == 5:
            part_count, point_count = struct.unpack_from("<II", body, 36)
            parts = list(struct.unpack_from(f"<{part_count}I", body, 44))
            points_offset = 44 + part_count * 4
            points = [struct.unpack_from("<dd", body, points_offset + 16 * i) for i in range(point_count)]
            parts.append(point_count)
            result.append([points[parts[i] : parts[i + 1]] for i in range(part_count)])
        else:
            raise ValueError(f"Unsupported SHP record type {shape_type}")
        offset = body_end
    return result


def multipolygon_wkt(rings: list[list[tuple[float, float]]]) -> str:
    # ESRI orientation identifies exteriors (clockwise) and holes (counterclockwise).
    # Use containment instead of record order because ring order is not significant.
    exteriors: list[list[list[tuple[float, float]]]] = []
    holes: list[list[tuple[float, float]]] = []
    for ring in rings:
        if signed_area(ring) < 0:
            exteriors.append([ring])
        else:
            holes.append(ring)
    for hole in holes:
        owners = [polygon for polygon in exteriors if contains_point(polygon[0][:-1], hole[0])]
        if not owners:
            raise ValueError("Interior ring is not contained by an exterior ring")
        min(owners, key=lambda polygon: abs(signed_area(polygon[0]))).append(hole)

    def format_ring(ring: list[tuple[float, float]]) -> str:
        return "(" + ",".join(f"{x:.3f} {y:.3f}" for x, y in ring) + ")"

    return "MULTIPOLYGON(" + ",".join(
        "(" + ",".join(format_ring(ring) for ring in polygon) + ")" for polygon in exteriors
    ) + ")"


def sql_literal(text: str) -> str:
    return "'" + text.replace("'", "''") + "'"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("shapefile_dir", type=pathlib.Path)
    parser.add_argument("output_sql", type=pathlib.Path)
    args = parser.parse_args()
    base = args.shapefile_dir / "limite_municipal"
    rows = read_dbf(base.with_suffix(".dbf"))
    shapes = read_shapes(base.with_suffix(".shp"))
    if len(rows) != len(shapes):
        raise ValueError("DBF and SHP row counts differ")
    statements = [
        "-- Polígonos oficiales IIEG, fuente EPSG:6368, transformados a EPSG:4326 por PostGIS.",
        "INSERT INTO viajes.amg_municipalities (municipality_code, municipality_name, geom, source_updated_at) VALUES",
    ]
    values = []
    found = set()
    for row, rings in zip(rows, shapes):
        code = row.get("clave_geo", "")
        if code not in TARGETS:
            continue
        name = TARGETS[code]
        if row.get("nombre") != name:
            raise ValueError(f"Name/code mismatch for {code}: {row.get('nombre')}")
        found.add(code)
        wkt = multipolygon_wkt(rings)
        values.append(
            "    (" + ", ".join((sql_literal(code), sql_literal(name),
                "ST_Multi(ST_Transform(ST_GeomFromText(" + sql_literal(wkt) + ", 6368), 4326))",
                "DATE '2026-10-06'")) + ")"
        )
    if found != set(TARGETS):
        raise ValueError(f"Missing municipality codes: {sorted(set(TARGETS) - found)}")
    statements.extend(",\n".join(values).splitlines())
    statements.append(
        "ON CONFLICT (municipality_code) DO UPDATE SET municipality_name = EXCLUDED.municipality_name, geom = EXCLUDED.geom, source_updated_at = EXCLUDED.source_updated_at;"
    )
    args.output_sql.write_text("\n".join(statements) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
