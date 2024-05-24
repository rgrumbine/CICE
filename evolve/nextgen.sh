#!/bin/sh

# link parents points to directory with all the previous parameter sets
# make a directory to save + point to for next gen
mkdir gen6

# parm.gen2 is the full parameter set
# fatal is the collection of fatal mutations
# final argument is the list of parent numbers
python3 descend.py parm.gen2 fatal gen6in

./torun.sh
mv set_nml.evo* exptlist.ts gen6
