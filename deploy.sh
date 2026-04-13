#!/bin/bash
vagrant up
ansible-playbook ansible/site.yml --ask-vault-pass