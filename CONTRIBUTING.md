# Contributing to dre_utils

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Before you start

- **Bugs and ideas:** open an issue first. For a bug, include the `dre --version` output, the
  database you run against, and the report (YAML and SQL) that shows the problem.
- **New macros:** open an issue to discuss the macro and its arguments before writing it.
- **Security problems:** don't open a public issue. Report them privately through the
  repository's **Security → Report a vulnerability** tab.

## How changes get in

`master` is protected. Nobody pushes to it directly:

1. Fork the repository and create a branch from `master`.
2. Make your change, with tests (see below), and sign off every commit (see below).
3. Open a pull request against `master` and describe what it changes and why.
4. CI must pass, and a maintainer must approve the pull request. New commits after an approval
   need a fresh one, and every review conversation must be resolved.
5. A maintainer merges it, squashing it into a single commit.

## Sign your commits off

dre_utils is licensed under [Apache-2.0](LICENSE), and contributions are accepted under the same
license. Sign off each commit to certify the
[Developer Certificate of Origin](https://developercertificate.org/): that you wrote the change,
or otherwise have the right to submit it under this license.

```sh
git commit -s -m "Add a macro for ..."
```

This adds a `Signed-off-by: Your Name <you@example.com>` line to the commit message.

## Testing

`integration_tests/` is a DRE project that uses this package from `..`. With `dre` on your
`PATH`:

```sh
cd integration_tests
dre deps        # installs the DuckDB, csv and slack plugins
./run.sh
```

`run.sh` runs every report against an in-memory DuckDB and compares each output with
`expected/`, and each error case with `errors.txt`. The reports tagged `slack` are run with
`--preview` against a Slack destination that never posts: the Block Kit JSON each component
renders to must match `expected/slack__<output>.json`. Then it runs the package's data tests.

## Guidelines

- **Keep pull requests focused:** one change per pull request.
- **Tests:** add a report under `integration_tests/reports/` with its expected output for each
  new macro or behaviour, and an error case for each new error.
- **Any database:** macros must produce SQL that works on every database DRE reads from. Put
  database-specific SQL in a `<source type>__<macro>` variant chosen through `dispatch()`.
- **Docs:** document new macros and arguments in `README.md`.
- **Your own work only:** submit only code you wrote, or code whose license allows it to be
  included here (say where it came from in the pull request).

## Code of conduct

Be respectful and constructive. Maintainers may remove comments, or block people, who aren't.
