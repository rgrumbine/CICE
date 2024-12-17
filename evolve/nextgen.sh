#!/bin/sh

export old=gen8
export next=gen9

# link parents points to directory with all the previous parameter sets
if [ -d parents ] ; then
  rm parents
fi
ln -s $old parents

# make a directory to save + point to for next gen
if [ ! -d $next ] ; then
  mkdir $next
fi

# parm.gen2 is the full parameter set
# fatal is the collection of fatal mutations
# final argument is the list of parent numbers
python3 descend.py parm.gen2 fatal ${next}in

./torun.sh
mv set_nml.evo* exptlist.ts ${next}
