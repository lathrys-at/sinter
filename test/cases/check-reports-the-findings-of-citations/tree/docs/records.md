# Records

@decision login v2
Users log in with a password.

## Logout

@decision logout v1
@deprecated
Users log out after an hour.

## Old store

@decision old-store v1
@supersedes new-store v1

## New store

@decision new-store v1
@supersedes old-store v1

## Store

@design store v1
@cites login v2
The store keeps the sessions.
