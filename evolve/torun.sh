#!/bin/sh

export OPT=$HOME/rgdev/CICE/configuration/scripts/options

if [ $OPT != "" ] ; then
  rm $OPT/set_nml.evo?*
  rm $OPT/../tests/exptlist.ts

  cp -p set_nml.evo* $OPT
  cp -p exptlist.ts $OPT/../tests
else
  echo must export OPT, pointing to the configuration/scripts/options directory
fi
