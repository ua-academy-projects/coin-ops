#!/bin/bash

vagrant up vm1 --color &
sleep 2
vagrant up vm2 --color &
sleep 2
vagrant up vm3 --color &
sleep 2
vagrant up vm4 --color &

wait
echo "All VMs are ready to work"