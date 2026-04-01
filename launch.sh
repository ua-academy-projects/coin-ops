#!/bin/bash

vagrant up vm1 --color &
sleep 3
vagrant up vm2 --color &
sleep 3
vagrant up vm3 --color &
sleep 3
vagrant up vm4 --color &
sleep 3
vagrant up vm5 --color &

wait
echo "All VMs are ready to work"