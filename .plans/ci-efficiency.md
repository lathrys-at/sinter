# CI efficiency
@plan ci-efficiency
@scope .github/workflows/**, test/**
Keep the caches of `main` in use between pushes, and shorten the wait
in the CLI tests that start a process with a time limit.

## Run the cached jobs in the daily run
@scope .github/workflows/**
Run the build, format, coverage, and bridge crate jobs in the daily
scheduled run too, so that a run reads each cache of `main` every day.
GitHub removes a cache that no run reads for seven days.

## Check the child process sooner in the CLI tests
@scope test/**
Wait 1 ms before the first check of a child process, and double the
wait after each check, up to 50 ms. The time limit of each test stays
the same.
