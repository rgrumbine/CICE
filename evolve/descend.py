import sys
import csv
from math import *
import numpy
import copy

"""
Types of parameters and their variation:
* T/F
* List of numbers
* List of character strings (e.g. 'bubbly')
* Arithmetic range e.g. [0,1]
* Logarithmic range e.g. [0.1x, 10x]

name, reference value, variations allowed
for ranges, min/max order on input

"""
"""
Class to implement variations on parameters
"""
rngf = numpy.random.default_rng()

class evo_parameters:

  def __init__(self, name="", reference="", ranges=""):
    self.name = name

    # determine type of variation
    if (ranges[0] == 'L'):
      self.type = 'log'
      w1 =ranges.split(' ')
      words = w1[1].split(',')

      tmp = reference.strip('\'')
      self.reference = float(tmp)
      tmp1 = log(float(words[0]))
      tmp2 = log(float(words[1]))
      self.ranges= [tmp1, tmp2]

    elif (ranges[0] == 'A'):
      self.type = 'arith'
      self.reference = float(reference.strip('\'') )
      w1 =ranges.split(' ')
      words = w1[1].split(',')
      self.ranges= [float(words[0]), float(words[1]) ]

    else:
      self.reference = reference.strip()
      words = ranges.split(',')
      self.type = 'list'
      self.ranges = ranges

  def show(self, fname=sys.stdout ):
    print(self.name, ";", self.reference,";",  self.type,";",  self.ranges,file=fname)

  def namelist(self, fname=sys.stdout ):
    # suitable for use as namelist input
      print(self.name, "=", self.reference, file=fname)

  def vary(self, fname = sys.stdout):
    if (self.type == 'log'):
      tmp = rngf.random()
      tmp *= (self.ranges[1]-self.ranges[0])
      tmp += self.ranges[0]
      self.reference *= exp(tmp)

    elif (self.type == 'arith'):
      #uniform float random in [0,1):
      tmp = rngf.random()
      tmp *= (self.ranges[1]-self.ranges[0])
      tmp += self.ranges[0]
      self.reference = tmp

    elif (self.type == 'list'):
      words = self.ranges.strip(' ')
      w2 = words.split(',')
      n = len(w2)
      k = rngf.integers(low = 0, high = n)
      self.reference = w2[k].strip()

    else:
      print("unknown variation type ",self.type, flush=True)

class fatal:

    def __init__(self, name="", fatal_val=""):
      self.name = name
      self.fatal_val = fatal_val

#friend outside class
def isfatal(name, val, fatalities):
  retcode = False
  for i in range(0,len(fatalities)):
    if (name == fatalities[i].name):
        if (val == fatalities[i].fatal_val):
            retcode = True
            return retcode
  return retcode

# take the given strain (fname) and the general parameter set with its allowed variations
#    and mutate
def descent(fname, parmset, pvary, nnml, exptlist):
    # Update reference parameter set with this experiment's values
    # Read in parent's mods:
    tparmset = copy.deepcopy(parmset)
    nparm = len(tparmset)
    fin = open(fname, "r")
    tmp = []
    for line in fin:
      words = line.split('=')
      name = words[0].strip()
      val  = words[1].strip()
      tmp.append([name, val])
      for i in range(0, nparm):
          if (name == tparmset[i].name):
              tparmset[i].reference = val
              break
    fin.close()

    # Now ensure at least one change
    fout = open("set_nml.evo"+"{:d}".format(nnml),"w")
    nvaried = 0
    while (nvaried == 0):
      for k in range(0, nparm):
        tries = 0
        if (rngf.random() < pvary):
          nvaried += 1
          while ((parmset[k].reference == tparmset[k].reference) and (tries < 10) 
                    and not isfatal(tparmset[k].name, tparmset[k].reference, fatalities) ):
            tparmset[k].vary()
            tries += 1
          if ( tries > 9) :
            print("tries = ",tries,tparmset[k].type, flush=True)

    for k in range(0, nparm):
        if (not (parmset[k].reference == tparmset[k].reference) ):
          tparmset[k].namelist(fname = fout)
    fout.close()
    print("smoke  gx3  1x1  med3,yr_out,evo"+"{:d}".format(nnml),file=exptlist)

#-------- Begin Execution ------------------------------------------------
#
# Read in full evolutionary control file:
parmset = []
count = 0
fin = open(sys.argv[1], "r")
for line in fin:
  if (';' in line):
    words = line.split(';')
    name = words[0].strip()
    reference = words[1].strip()
    ranges = words[2].strip()

    x = evo_parameters(name, reference, ranges)
    parmset.append(x)
    count += 1
fin.close()

# Read in fatal mutations
fatalities = []
fin = open(sys.argv[2],"r")
for line in fin:
  words = line.split('=')
  name  = words[0].strip()
  val   = words[1].strip()
  tmp   = copy.deepcopy(fatal(name, val))
  fatalities.append(tmp )
fin.close()

# Read in parents:
nos = []
exptnos = open(sys.argv[3], "r")
for k in exptnos:
  nos.append(int(k))
jmax      = int(len(nos))

# Establish basic parameters for conducting evolution:
pvary     = 1./float(count)
nexpt_ref = 120
ndescend  = int(nexpt_ref / jmax)

#debug: print(len(sys.argv), pvary, nexpt_ref, jmax, ndescend, flush=True)
#debug: exit(0)

exptlist = open("exptlist.ts","w")
print("# Test         Grid    PEs        Sets   ",file=exptlist)

# Run over each parent:
for j in range(0, jmax):
  fname = "parents/set_nml.evo"+"{:d}".format(nos[j])
  # Generate descendants:
  for i in range(0, ndescend):
    descent(fname, parmset, pvary, j*ndescend+i, exptlist)

exptlist.close()
