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

class parmvary:

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
      #debug: print('log',flush=True)
      tmp = rngf.random()
      tmp *= (self.ranges[1]-self.ranges[0])
      tmp += self.ranges[0]
      #debug: print('log uniform random ',tmp, self.ranges[0], self.ranges[1], flush=True)
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


#-----------------------------------------------------------------------
# Begin execution
fatalities = []
for line in open(sys.argv[2],"r"):
  words = line.split('=')
  name  = words[0].strip()
  val   = words[1].strip()
  tmp   = copy.deepcopy(fatal(name, val))
  fatalities.append(tmp )
#debug: print("number of fatalities",len(fatalities) , flush=True)
#debug: for i in range(0, len(fatalities) ):
#debug:   print(fatalities[i].name, fatalities[i].fatal_val, flush=True)
#debug: exit(0)


# Read in evolutionary control:
parmset = []
count = 0
for line in open(sys.argv[1], "r"):
  if (';' in line):
    words = line.split(';')
    name = words[0].strip()
    reference = words[1].strip()
    ranges = words[2].strip()

    x = parmvary(name, reference, ranges)
    parmset.append(x)
    count += 1

exptlist = open("exptlist.ts","w")
print("# Test         Grid    PEs        Sets   ",file=exptlist)

## For generation1: Change 1 and only 1 parameter, but ensure that it does get changed
#for k in range(0, count):
#
#  tmp = copy.deepcopy(parmset)
#  fout = open("set_nml.evo"+"{:d}".format(k),"w")
#  tries = 0
#  while ((tmp[k].reference == parmset[k].reference) and (tries < 10) ):
#    tmp[k].vary()
#    tries += 1
#  if ( tries > 9) :
#    print("tries = ",tries,tmp[k].type, flush=True)
#  else:
#    tmp[k].namelist(fname = fout)
#    print("smoke  gx3  1x1  med3,yr_out,evo"+"{:d}".format(k),file=exptlist)
#
#  fout.close()


# For generation2: Avoid fatal variations, p(vary) = 1/count. If n(varied) == 0, retry
pvary   = 1./float(count)
# Number of experiments, need not equal number of parameters
for nexpts in range (0, count):
  tmp = copy.deepcopy(parmset)
  fout = open("set_nml.evo"+"{:d}".format(nexpts),"w")
  nvaried = 0
  while (nvaried == 0):
    for k in range(0, count):
      tries = 0
      if (rngf.random() < pvary):
        nvaried += 1
        while ((tmp[k].reference == parmset[k].reference) and (tries < 10) 
                  and not isfatal(tmp[k].name, tmp[k].reference, fatalities) ):
          tmp[k].vary()
          tries += 1
        if ( tries > 9) :
          print("tries = ",tries,tmp[k].type, flush=True)
  
  for k in range(0, count):
      if (not (tmp[k].reference == parmset[k].reference) ):
        tmp[k].namelist(fname = fout)
  fout.close()

  print("smoke  gx3  1x1  med3,yr_out,evo"+"{:d}".format(nexpts),file=exptlist)


exptlist.close()
