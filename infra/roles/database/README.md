# Database Role

This role installs and configures PostgreSQL for persisting historical event data. It is targeted at the `vm5` host.

## Tasks
1. Installs `postgresql` and `python3-psycopg2` packages.
2. Configures `postgresql.conf` (`listen_addresses = '*'`) and `pg_hba.conf` (allowing access from the `10.10.1.0/24` subnet).
3. Creates the required database user and the target database (fetching credentials from Vault).
4. Templates and executes the initialization script (`init.sql.j2`), creating the `exchange_rates` schema and its indices.
5. Enables and starts the `postgresql` systemd service.

## Role Variables
Expects the following variables from `group_vars/all`:
- `pg_database` (from vars.yml)
- `pg_user` (plaintext, from vault.yml)
- `pg_password` (encrypted, from vault.yml)

## Dependencies
It is highly recommended to run the `base` role prior to this one for proper DNS and basic utilities.
