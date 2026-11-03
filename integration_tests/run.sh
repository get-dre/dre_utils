#!/usr/bin/env bash
# Runs the integration tests against `dre` on the PATH (or $DRE): the reports tagged `ok` must
# produce exactly the files in expected/ (the Binding's `current` names the run folder they are
# in), and each report tagged `error` must fail with the message listed in errors.txt. The
# reports declaring this package's data tests then run with `dre test`.
set -euo pipefail
cd "$(dirname "$0")"
dre="${DRE:-dre}"
export DRE_RUN_DATE=2026-03-18
# An in-memory DuckDB: each report creates the tables it needs.
profiles="$(mktemp -d)"
yaml=reports/data_tests_report/data_tests.yml
cleanup() {
  if [[ -f "$profiles/original.yml" ]]; then cp "$profiles/original.yml" "$yaml"; fi
  rm -f "$yaml.cut"
  rm -rf "$profiles"
}
trap cleanup EXIT
printf 'sources:\n  memory:\n    target: dev\n    targets:\n      dev: {type: duckdb, path: ":memory:"}\n' > "$profiles/profiles.yml"
rm -rf target
"$dre" run -s tag:ok --profiles-dir "$profiles"
status=0
for f in expected/*.csv; do
  name="$(basename "$f")"
  report="${name%%__*}"
  tab="${name#*__}"
  run="$(cat "target/run/$report/default/current")"
  got="target/run/$report/default/runs/$run/$tab"
  if ! diff -u "$f" "$got"; then
    echo "FAIL: $got differs from $f"
    status=1
  fi
done
while IFS=$'\t' read -r report message; do
  [[ -z "$report" ]] && continue
  if out="$("$dre" run -s "$report" --profiles-dir "$profiles" 2>&1)"; then
    echo "FAIL: $report ran, but should fail with: $message"
    status=1
  elif [[ "$out" != *"$message"* ]]; then
    echo "FAIL: $report failed without: $message"
    echo "$out"
    status=1
  fi
done < errors.txt
# The package's data tests. Each check's status and failure-row count, where zero rows is a pass,
# is in its query's run: a data failure stops its Binding, so the report as declared runs its
# first query with checks. The checks later in the report get runs of their own, over the report
# cut after their query.
checks="$profiles/checks"
: > "$checks"
runs="target/run/data_tests_report/default/runs"
collect() {
  python3 - "$1" >> "$checks" <<'PY'
import glob, json, sys
# Keep the complete published result contract, including skips without failure counts.
for path in glob.glob(f"{sys.argv[1]}/*/run_results.json"):
    for check in json.load(open(path)).get("tests", []):
        print(json.dumps(check, sort_keys=True))
PY
}
"$dre" test -s data_tests_report --profiles-dir "$profiles" >/dev/null 2>&1 && code=0 || code=$?
[[ $code == 1 ]] || { echo "FAIL: data_tests_report exited $code, expected 1: it finds bad data"; status=1; }
collect "$runs"
# The report cut after one query: the earlier queries without checks (the seed and the expected
# results its checks read) and that query with its checks. The later queries go, as a failure
# would have stopped the report before them.
cp "$yaml" "$profiles/original.yml"
for check in "duplicate_keys fail" "no_rows fail" "negative_amount fail" "totals_pass pass" \
             "totals_within_tolerance pass" "totals_off fail" "totals_other_column pass" \
             "source_checks fail"; do
  read -r query want <<<"$check"
  python3 - "$profiles/original.yml" "$query" > "$yaml.cut" <<'PY'
import sys
path, last = sys.argv[1], sys.argv[2]
head = open(path).read().split("tags: [data_tests]")[0]
blocks = [[]]
for line in head.splitlines():
    if line.startswith(("  - query: ", "  - {query: ")):
        blocks.append([])
    blocks[-1].append(line)
names = [block[0].split("query:")[1].strip(" {,}") for block in blocks[1:]]
out = ["queries:"]
for name, block in zip(names, blocks[1:]):
    if name == last:
        out.extend(block)
    elif names.index(name) < names.index(last) and not any(l.startswith("      - ") for l in block):
        out.extend(block)
print("\n".join(out))
print("tags: [data_tests]")
PY
  cp "$yaml.cut" "$yaml"
  "$dre" test -s data_tests_report --profiles-dir "$profiles" >/dev/null 2>&1 && code=0 || code=$?
  cp "$profiles/original.yml" "$yaml"
  if { [[ "$want" == pass && $code != 0 ]] || [[ "$want" != pass && $code != 1 ]]; }; then
    echo "FAIL: $query: its checks exited $code, but should $want"
    status=1
  fi
  collect "$runs"
  rm -rf "$runs"
done
rm -f "$yaml.cut"
# What each check must do: its query, its name, its execution, and its failure-row count (zero
# passes). The full-report run also records checks skipped after an earlier error; assert those
# states too. An unlisted check fails, as does an expected check that never runs.
python3 - "$checks" <<'PY' || status=1
import json, sys
want = {
    ("clean_ids", "not_null"): (0, "local", 1),
    ("duplicate_keys", "unique"): (1, "local", 1),
    ("no_rows", "not_empty"): (1, "local", 1),
    ("negative_amount", "non_negative"): (1, "local", 1),
    ("totals_pass", "totals_match"): (0, "local", 1),
    ("totals_within_tolerance", "totals_match"): (0, "local", 1),
    ("totals_off", "totals_match"): (1, "local", 1),
    ("totals_other_column", "totals_match"): (0, "local", 1),
    ("source_checks", "not_null"): (0, "source", 1),
    ("source_checks", "unique"): (0, "source", 2),
    ("source_checks", "non_negative"): (1, "source", 3),
    ("source_checks", "totals_match"): (1, "source", 4),
    ("source_checks", "not_empty"): (1, "source", 5),
}
seen = {}
for line in sorted(open(sys.argv[1])):
    check = json.loads(line)
    query, name = check["query"], check["test"].removeprefix("dre_utils.")
    key = (query, name)
    if not isinstance(check.get("query_ordinal"), int) or check["query_ordinal"] < 1:
        raise ValueError(f"{key}: invalid query_ordinal in {check}")
    record = {field: value for field, value in check.items() if field != "duration_ms"}
    seen.setdefault(key, {})[json.dumps(record, sort_keys=True)] = check
bad = []
for key in list(want) + [k for k in seen if k not in want]:
    rows = list(seen.get(key, {}).values())
    executed = [row for row in rows if row.get("status") in ("pass", "fail")]
    skipped = [row for row in rows if row.get("status") == "skipped"]
    failures, execution, ordinal = want.get(key, (None, None, None))
    expected_executions = 2 if key == ("duplicate_keys", "unique") else 1
    expected_skips = (
        1 if list(want).index(key) > list(want).index(("duplicate_keys", "unique")) else 0
    ) if key in want else -1
    ok = (
        key in want
        and len(executed) == expected_executions
        and all(row.get("status") == ("pass" if failures == 0 else "fail") for row in executed)
        and all(row.get("failures") == failures for row in executed)
        and all(row.get("severity") == "error" for row in executed)
        and all(row.get("execution") == execution for row in executed)
        and all(row.get("ordinal") == ordinal for row in executed)
        and len(skipped) == expected_skips
        and all(
            row.get("skip_reason") == "data-test-failed"
            and "failures" not in row
            and row.get("severity") == "error"
            and row.get("execution") == execution
            and row.get("ordinal") == ordinal
            for row in skipped
        )
        and len(rows) == len(executed) + len(skipped)
    )
    if not ok:
        bad.append(f"{key}: {rows}, expected {want.get(key)} and its published status fields")
for line in bad:
    print(f"FAIL: {line}")
print(f"data tests: {len(want)} checks, {len(bad)} unexpected")
sys.exit(1 if bad else 0)
PY
# The package installed the way `dre deps` installs one from Git: a copy of this checkout, in a
# local Git repository outside this one, with a project that declares it. So the install needs no
# network, and its checks must still resolve through the package's namespace: `dre test` runs them
# and finds the bad data.
evidence="$profiles/git"
mkdir -p "$evidence/package" "$evidence/project/reports"
cp ../dre_package.yml "$evidence/package/"
cp -R ../macros "$evidence/package/"
cp -R reports/git_package "$evidence/project/reports/"
cp dre_project.yml "$evidence/project/"
revision=none
(
  cd "$evidence/package" || exit 1
  export GIT_CEILING_DIRECTORIES="$PWD"
  git init --quiet . || exit 1
  git add --all &&
  GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z \
    git -c user.name=dre -c user.email=dre@example.invalid commit \
      --quiet -m "the package under test"
) && revision="$(git -C "$evidence/package" rev-parse HEAD)"
printf 'plugins: [duckdb, csv]\npackages:\n  - git: %s/package\n    revision: %s\n' \
  "$evidence" "$revision" > "$evidence/project/dependencies.yml"
if (cd "$evidence/project" && "$dre" deps >/dev/null 2>&1); then
  (cd "$evidence/project" && "$dre" test -s git_package --profiles-dir "$profiles" \
     > "$evidence/log" 2>&1) && code=0 || code=$?
  [[ $code == 1 ]] || { echo "FAIL: Git package exited $code, expected 1"; status=1; }
  # Exit 1 also covers render/runtime errors: require the exact completed checks.
  python3 - "$evidence/project/target/run/git_package/default" <<'PY_CHECK' || status=1
import json, pathlib, sys
binding = pathlib.Path(sys.argv[1])
try:
    result = json.loads((binding / "runs" / (binding / "current").read_text().strip() / "run_results.json").read_text())
    got = [(t["query"], t["test"], t["execution"], t["severity"], t["ordinal"], t["status"], t.get("failures")) for t in result["tests"]]
    want = [("clean_ids", "dre_utils.not_null", "local", "error", 1, "pass", 0),
            ("clean_ids", "dre_utils.not_empty", "source", "error", 2, "fail", 1)]
    if got != want:
        raise ValueError(f"got {got!r}, expected {want!r}")
    if any(not isinstance(t["query_ordinal"], int) or t["query_ordinal"] < 1 for t in result["tests"]):
        raise ValueError(f"invalid query_ordinal in {result['tests']!r}")
except (OSError, KeyError, ValueError) as error:
    print(f"FAIL: Git package checks: {error}")
    sys.exit(1)
print("git package: local not_null passed (0), source not_empty failed (1)")
PY_CHECK
else
  echo "FAIL: dre deps does not install this checkout from Git"
  status=1
fi
[[ $status == 0 ]] && echo "All integration tests passed."
exit $status
