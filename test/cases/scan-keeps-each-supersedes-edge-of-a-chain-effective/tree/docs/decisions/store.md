# Keep sessions in memory

@decision memory-store
Sessions live in memory.

## Keep sessions in a file

@decision file-store v2
@supersedes memory-store v1
Sessions live in one file.

## Keep sessions in a database

@decision database-store v3
@supersedes file-store v2
Sessions live in a database.
