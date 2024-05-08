#!/bin/sh

if [ $OPT != "" ] ; then
  cp -p set_nml.evo* $OPT
  cp -p exptlist.ts $OPT/../tests
else
  echo must export OPT, pointing to the configuration/scripts/options directory
fi
