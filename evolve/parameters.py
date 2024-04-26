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

import sys
import csv
import numpy
import copy


"""
Class to implement variations on parameters
"""
class parmvary:
  def __init__(self, name="", reference="", ranges=""):
    self.name = name
    self.reference = reference
    # determine type of variation
    if (ranges[0] == 'L'):
      print("logarithmic")
      self.ranges=ranges 
      self.type = 'log'
    elif (ranges[0] == 'A'):
      print("arithmetic")
      self.ranges=ranges 
      self.type = 'arith'
    else:
      words = ranges.split(',')
      print('list', len(words))
      for i in range(0,len(words)):
        print(" ",words[i].strip() )
      self.ranges = ranges 
      self.type = 'list'
 

parmset = []

# Begin execution
count = 0
for line in open(sys.argv[1], "r"):
  if (';' in line):
    words = line.split(';')
    #debug: print(words)
    name = words[0].strip()
    reference = words[1].strip()
    ranges = words[2].strip()
    #debug: print(name)
    x = parmvary(name, reference, ranges)
    parmset.append(x)
    count += 1

#print(count, len(parmset) )
#for i in range(0, count):
#  print(parmset[i].name)
