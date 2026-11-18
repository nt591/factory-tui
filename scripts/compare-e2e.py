#!/usr/bin/env python3
"""Compare compatible completed E2E perf reports without enforcing timing gates."""

import argparse
import json
import math
import re
from pathlib import Path

LAUNCH_ACTIONS = {
    "sqlite_startup",
    "sqlite_shutdown",
    "replay_startup_backlog",
    "automatic_ready",
}
INTERACTION_ACTIONS = {
    "board_search",
    "board_reset",
    "card_navigation",
    "chat_expand",
    "composer_open",
    "paste",
    "queue_reply",
    "history_top",
    "history_latest",
    "chat_return",
    "board_focus",
    "stream_replacement",
}
COMPATIBILITY = (
    "schema_version",
    "parameters",
    "platform",
    "architecture",
    "python_version",
    "pyte_version",
    "benchmark_sha256",
    "scope",
    "measurement",
    "resource_scope",
)


def number(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def summary(samples):
    ordered = sorted(samples)
    middle = len(ordered) // 2
    return {
        "median_ms": ordered[middle]
        if len(ordered) % 2
        else (ordered[middle - 1] + ordered[middle]) / 2,
        "p95_ms": ordered[math.ceil(len(ordered) * 0.95) - 1],
        "max_ms": ordered[-1],
    }


def validate(report):
    if (
        not isinstance(report, dict)
        or report.get("status") != "passed"
        or report.get("schema_version") != 1
    ):
        raise ValueError("Only completed schema-version-1 reports can be compared.")
    parameters = report.get("parameters")
    if not isinstance(parameters, dict):
        raise TypeError("Missing workload parameters.")
    for key in ("runs", "interactions", "tasks", "messages", "columns", "rows"):
        if type(parameters.get(key)) is not int or parameters[key] <= 0:
            raise ValueError(f"Invalid parameter: {key}.")
    if not number(parameters.get("timeout")) or parameters["timeout"] == 0:
        raise ValueError("Invalid parameter: timeout.")
    for key in COMPATIBILITY[2:]:
        if not isinstance(report.get(key), str) or not report[key]:
            raise ValueError(f"Missing measurement metadata: {key}.")
    for key in ("binary_sha256", "benchmark_sha256"):
        if not re.fullmatch(r"[0-9a-f]{64}", report.get(key, "")):
            raise ValueError(f"Invalid hash: {key}.")
    if type(report.get("binary_bytes")) is not int or report["binary_bytes"] <= 0:
        raise ValueError("Invalid executable size.")
    latency = report.get("latency")
    if (
        not isinstance(latency, dict)
        or set(latency) != LAUNCH_ACTIONS | INTERACTION_ACTIONS
    ):
        raise ValueError("Report does not contain the complete measured action set.")
    for action, entry in latency.items():
        count = parameters["runs"] * (
            1 if action in LAUNCH_ACTIONS else parameters["interactions"]
        )
        if not isinstance(entry, dict):
            raise TypeError(f"Invalid latency entry: {action}.")
        samples = entry.get("samples_ms")
        if (
            not isinstance(samples, list)
            or len(samples) != count
            or not all(number(v) for v in samples)
        ):
            raise ValueError(f"Incomplete or invalid samples: {action}.")
        if type(entry.get("count")) is not int or entry["count"] != count:
            raise ValueError(f"Incorrect sample count: {action}.")
        for key, expected in summary(samples).items():
            if not number(entry.get(key)) or not math.isclose(
                entry[key], expected, rel_tol=1e-12, abs_tol=1e-9
            ):
                raise ValueError(f"Summary does not match raw samples: {action}/{key}.")
    resources = report.get("resources")
    if not isinstance(resources, list) or len(resources) != parameters["runs"] * 2:
        raise ValueError("Incomplete resource samples.")
    expected = {
        (workload, iteration)
        for workload in ("sqlite", "replay")
        for iteration in range(parameters["runs"])
    }
    seen = set()
    for entry in resources:
        if (
            not isinstance(entry, dict)
            or type(entry.get("iteration")) is not int
            or entry.get("workload") not in ("sqlite", "replay")
        ):
            raise ValueError("Invalid resource identity.")
        identity = (entry["workload"], entry["iteration"])
        if identity not in expected or identity in seen:
            raise ValueError("Duplicate or unexpected resource sample.")
        seen.add(identity)
        for key in (
            "child_user_cpu_seconds",
            "child_system_cpu_seconds",
            "observer_cpu_seconds",
            "observed_terminal_bytes",
        ):
            if not number(entry.get(key)):
                raise ValueError(f"Invalid resource observation: {key}.")
        memory = entry.get("rss_samples_bytes")
        if (
            not isinstance(memory, list)
            or len(memory) != 2
            or not all(number(v) for v in memory)
        ):
            raise ValueError("Invalid sampled RSS.")


def delta(baseline, candidate):
    return {
        "baseline": baseline,
        "candidate": candidate,
        "difference": candidate - baseline,
        "percent": None if baseline == 0 else (candidate / baseline - 1) * 100,
    }


def compare(baseline, candidate):
    validate(baseline)
    validate(candidate)
    differences = [key for key in COMPATIBILITY if baseline[key] != candidate[key]]
    if differences:
        raise ValueError(
            "Incompatible measurement reports: " + ", ".join(differences) + "."
        )
    latency = {
        action: {
            key: delta(
                baseline["latency"][action][key], candidate["latency"][action][key]
            )
            for key in ("median_ms", "p95_ms", "max_ms")
        }
        for action in sorted(baseline["latency"])
    }
    resources = {}
    for workload in ("sqlite", "replay"):

        def aggregate(report, workload=workload):
            rows = [
                entry for entry in report["resources"] if entry["workload"] == workload
            ]
            return {
                "maximum_sampled_rss_bytes": max(
                    max(row["rss_samples_bytes"]) for row in rows
                ),
                **{
                    key: sum(row[key] for row in rows) / len(rows)
                    for key in (
                        "child_user_cpu_seconds",
                        "child_system_cpu_seconds",
                        "observer_cpu_seconds",
                        "observed_terminal_bytes",
                    )
                },
            }

        left, right = aggregate(baseline), aggregate(candidate)
        resources[workload] = {key: delta(left[key], right[key]) for key in left}
    return {
        "status": "compared",
        "baseline_binary_sha256": baseline["binary_sha256"],
        "candidate_binary_sha256": candidate["binary_sha256"],
        "notice": "Positive deltas mean larger observed cost. No significance test or timing gate. Compatible metadata does not prove identical hardware/load or terminal GUI paint latency.",
        "binary_bytes": delta(baseline["binary_bytes"], candidate["binary_bytes"]),
        "latency": latency,
        "resources": resources,
    }


def read(path):
    if path.stat().st_size > 8 * 1024 * 1024:
        raise ValueError("Report exceeds the 8 MiB input limit.")
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument(
        "--json", action="store_true", help="Print structured comparison to stdout."
    )
    args = parser.parse_args()
    try:
        result = compare(read(args.baseline), read(args.candidate))
    except (OSError, ValueError, TypeError) as error:
        parser.exit(2, f"Cannot compare: {error}\n")
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(result["notice"])
        print(
            "Action                         median ms (before -> after)     delta       p95 delta"
        )
        for action, values in result["latency"].items():
            median, p95 = values["median_ms"], values["p95_ms"]
            percent = (
                "n/a" if median["percent"] is None else f"{median['percent']:+.1f}%"
            )
            print(
                f"{action:30} {median['baseline']:9.3f} -> {median['candidate']:9.3f}  {percent:>8}   {p95['difference']:+.3f} ms"
            )
        for workload, observations in result["resources"].items():
            print(
                f"\n{workload} resources (CPU/bytes: mean per launch; RSS: maximum sample, not peak):"
            )
            for key, values in observations.items():
                print(f"  {key}: {values['baseline']:.3f} -> {values['candidate']:.3f}")


if __name__ == "__main__":
    main()
