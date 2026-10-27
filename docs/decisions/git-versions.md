<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Support the git versions that still get security fixes
@decision git-versions
Sinter supports each git version of a maintenance track that the last security release of git covered, and states the oldest one as its minimum.

## Context

Sinter reads a repository only through the `git` program. The code
said that it needed git 2.30 or later, but nobody had given a reason
for 2.30. Diff mode sets `GIT_NO_LAZY_FETCH=1`, so that git never
downloads a missing object in a partial clone. Git reads that variable
only from the security releases of April 2024: 2.39.4, 2.40.2, 2.41.1,
2.42.2, 2.43.4, 2.44.1, and 2.45.1 and later.

Git has no long-term support. Its security policy supports only the
maintenance track of the newest feature release, 2.56 in October
2026. In practice, git also gives critical security fixes to some
older tracks. The last such release, in June 2025, covered the tracks
from 2.43 to 2.50, with 2.43.7 as the oldest version. Long-term
distributions ship older tracks: Ubuntu 24.04 ships 2.43.0 with
Ubuntu's own security fixes, and Debian 13 ships 2.47. The git of
Xcode on macOS was 2.54.0.

## Decision

- Sinter supports a git version when its maintenance track had a
  release in the last security release of git. The oldest version of
  that release is the minimum: 2.43.7 in October 2026.
- The minimum rises only when a new security release of git leaves
  out the oldest track.
- A distribution's build of an older version string that carries the
  same security fixes is supported, as Ubuntu's 2.43.0 is.
- `README.md` and `lib/git.mli` state the minimum. Sinter does not
  check the version of git when it runs.

## Alternatives considered

- **Only the newest feature release, as git's security policy
  says.** Not chosen: the minimum would rise about every three
  months, and it would exclude the git of Xcode and of every
  long-term Linux distribution.
- **The same versions, with a check of the version when Sinter
  runs.** Not chosen: a distribution keeps the old version string
  when it adds security fixes, so the check would refuse a supported
  git, such as Ubuntu's 2.43.0.

## Consequences

Every supported git reads `GIT_NO_LAZY_FETCH`. The code may use a
feature of git 2.43. A user of an older git gets no error from Sinter
and no promise from it. A person who changes the minimum looks at the
newest security release of git, and nothing reminds them.
