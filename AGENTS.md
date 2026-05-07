# AGENTS.md

## Project purpose
Legacy Vyatta system-level configuration scripts. **Deprecated**: per the in-repo `README`, "this package is deprecated and all it's content was rewritten" — replaced by `vyos/vyos-1x`. Retained only on LTS trains (sagitta/equuleus) for compatibility.

## Tech stack
- Shell + Perl + minor C/C++. Autotools (`configure.ac`, `Makefile.am`).
- Build deps (`debian/control`): `debhelper (>= 5)`, `autotools-dev`, `autoconf`, `automake`, `cpio`.
- Debian packaging via `dpkg-buildpackage`.

## Build / test / run
```
autoreconf -i &&./configure && make
dpkg-buildpackage -uc -us -tc -b
```
No standalone test harness.

## Repository layout
- `scripts/` — install-time and op-mode helper scripts.
- `sysconf/` — system configuration assets shipped to `/etc`.
- `debian/` — packaging.
- `README` — deprecation notice pointing at `vyos-1x`.

## Cross-repo context
Historical sibling of `vyos/vyatta-cfg`. Functionality migrated into `vyos/vyos-1x` (`src/conf_mode/`, `src/op_mode/`, `python/vyos/`). Still pulled into LTS ISO builds by `vyos/vyos-build` where required.

## Conventions
- Commit/PR title: `component: T12345: description`. Phorge IDs at https://vyos.dev.
- Reusable workflows: this repo carries an older workflow set (`pull-request-management.yml`, `mergifyio_backport.yml`, `pull-request-message-check.yml`, etc.) that predates the consolidation under `vyos/.github`. Edit only if the LTS train still needs them.
- Default branch is `current` for the canonical history; LTS branches `sagitta`/`equuleus` are where active backports land.

## Mirror relationship
Mirror twin: `VyOS-Networks/vyatta-cfg-system` (drifted; gen-1 mirror pipeline not confirmed live for this repo). Treat the `vyos/*` side as canonical.

## Notes for future contributors
- Do not add features here — extend `vyos-1x` instead. Acceptable changes are CVE/security backports for LTS trains.
- Preserve the deprecation notice in `README`; future work should not silently revive this package.
- The workflow set diverges from the modern `vyos/.github@current` reusable model; do not rewire without a coordinated update to the LTS branches.
