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
      #debug: print("logarithmic", flush=True)
      self.type = 'log'
      w1 =ranges.split(' ')
      words = w1[1].split(',')

      #debug: for i in range(0,len(words)):
      #debug:   print(i,'words(i)',words[i])

      tmp = reference.strip('\'')
      #debug: print("log tmp tmp.float ",tmp, float(tmp), flush=True)
      self.reference = float(tmp)
      tmp1 = log(float(words[0]))
      tmp2 = log(float(words[1]))
      self.ranges= [tmp1, tmp2]

    elif (ranges[0] == 'A'):
      #debug: print("arithmetic ",reference, 'ranges = ', ranges, flush=True)

      self.type = 'arith'
      self.reference = float(reference.strip('\'') )
      w1 =ranges.split(' ')
      words = w1[1].split(',')
      self.ranges= [float(words[0]), float(words[1]) ]

    else:
      self.reference = reference
      words = ranges.split(',')
      #debug: print('list', len(words), flush=True)
      #debug: for i in range(0,len(words)):
      #debug:   print(" ",words[i].strip() )
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
      #debug: print('arith',flush=True)
      #uniform float random in [0,1):
      tmp = rngf.random()
      tmp *= (self.ranges[1]-self.ranges[0])
      tmp += self.ranges[0]
      #debug: print('arith uniform random ',tmp, self.ranges[0], self.ranges[1])
      self.reference = tmp

    elif (self.type == 'list'):
      words = self.ranges.strip(' ')
      w2 = words.split(',')
      n = len(w2)
      #debug: print("number of characters in a 'list' variable ",n, flush=True)
      #debug: print("number of words in a 'list' variable ",n, w2, flush=True)
      k = rngf.integers(low = 0, high = n)
      #debug: print('list ', k, w2[k])
      self.reference = w2[k].strip(' ')

    else:
      print("unknown variation type ",self.type, flush=True)



parmset = []

# Begin execution
count = 0
for line in open(sys.argv[1], "r"):
  if (';' in line):
    words = line.split(';')
    #debug: print(words, flush=True)

    name = words[0].strip()
    reference = words[1].strip()
    ranges = words[2].strip()
    #debug: print('deb ',name, ';', reference,';',  ranges, flush=True)

    x = parmvary(name, reference, ranges)
    parmset.append(x)
    count += 1
#debug: print(count, len(parmset), flush=True )

#for i in range(0, count):
#  print(i,"  ",end="")
#  parmset[i].show()

fout = open("set_nml.evo1","w")
for i in range(0, count):
  parmset[i].vary()
  parmset[i].namelist(fname = fout)

