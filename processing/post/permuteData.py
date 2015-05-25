#!/usr/bin/env python
# -*- coding: UTF-8 no BOM -*-

import os,sys,string
import numpy as np
from optparse import OptionParser
import damask

scriptID   = string.replace('$Id$','\n','\\n')
scriptName = os.path.splitext(scriptID.split()[1])[0]

# --------------------------------------------------------------------
#                                MAIN
# --------------------------------------------------------------------

parser = OptionParser(option_class=damask.extendableOption, usage='%prog options [file[s]]', description = """
Permute all values in given column(s).

""", version = scriptID)

parser.add_option('-l','--label',   dest='label', action='extend', metavar='<string LIST>',
                  help='heading(s) of column to permute')
parser.add_option('-r', '--rnd',    dest='randomSeed', type='int', metavar='int',
                  help='seed of random number generator [%default]')
parser.set_defaults(randomSeed = None)

(options,filenames) = parser.parse_args()

if options.label == None:
  parser.error('no data column specified...')

# --- loop over input files -------------------------------------------------------------------------
for name in filenames:
  if not os.path.exists(name): continue
  file = {'name':name, 'input':open(name), 'output':open(name+'_tmp','w'), 'croak':sys.stderr}
  file['croak'].write('\033[1m'+scriptName+'\033[0m: '+file['name']+'\n')

  randomSeed = int(os.urandom(4).encode('hex'), 16)  if options.randomSeed == None else options.randomSeed         # radom seed per file for second phase
  np.random.seed(randomSeed)
  table = damask.ASCIItable(file['input'],file['output'],buffered=False)                            # make unbuffered ASCII_table
  table.head_read()                                                                                 # read ASCII header info
  table.info_append(scriptID + '\t' + ' '.join(sys.argv[1:]))
  table.info_append('random seed %i'%randomSeed)

# --------------- figure out columns to process  ---------------------------------------------------
  active = []
  column = {}

  for label in options.label:
    if label in table.labels:
      active.append(label)
      column[label] = table.labels.index(label)                                                     # remember columns of requested data
    else:
      file['croak'].write('column %s not found...\n'%label)
       
# ------------------------------------------ assemble header ---------------------------------------
  table.head_write()

# ------------------------------------------ process data ------------------------------------------
  permutation = {}
  table.data_readArray(active)
  for i,label in enumerate(active):
    unique = list(set(table.data[:,i]))
    permutated = np.random.permutation(unique)
    permutation[label] = dict(zip(unique,permutated))

  table.data_rewind()
  table.head_read()                                                                                 # read ASCII header info again to get the completed data
  outputAlive = True
  while outputAlive and table.data_read():                                                          # read next data line of ASCII table
    for label in active:                                                                            # loop over all requested stiffnesses
      table.data[column[label]] = permutation[label][float(table.data[column[label]])]                                    # apply permutation
    
    outputAlive = table.data_write()                                                                # output processed line

# ------------------------------------------ output result -----------------------------------------  
  outputAlive and table.output_flush()                                                              # just in case of buffered ASCII table

  table.input_close()                                                                               # close input ASCII table
  table.output_close()                                                                              # close output ASCII table
  os.rename(file['name']+'_tmp',file['name'])                                                       # overwrite old one with tmp new
