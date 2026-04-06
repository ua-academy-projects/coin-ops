# Base Role

This role is executed first for all hosts (`hosts: all`) in the environment. It configures basic utilities and system-wide settings.

## Tasks
1. Configures `systemd-resolved` to use public DNS clients (8.8.8.8, 1.1.1.1) to bypass NAT-DNS issues inside virtualizers. Performs a `flush_handlers` and restarts the service when updated.
2. Installs basic management packages: `iputils-ping`, `vim`, `curl`, `ufw`, `acl`.

## Role Variables
Does not rely on any role-specific variables or secrets.

## Dependencies
This role has no dependencies on other roles.
