import os,sys,string,re

class Environment():
  __slots__ = [ \
                'rootRelation',
                'pathInfo',
              ]

  def __init__(self,rootRelation = '.'):
    self.pathInfo = {\
                     'acml': '/opt/acml4.4.0',
                     'fftw': '.',
                     'msc':  '/msc',
                    }
    self.rootRelation = rootRelation                    
    self.get_pathInfo()

  def relPath(self,relative = '.'):
    return os.path.join(self.rootDir(),relative)

  def rootDir(self):
    damask_root = os.getenv('DAMASK_ROOT')
    if damask_root == '' or damask_root == None:            # env not set
      if sys.argv[0] == '':                                 # no caller path
        cwd = os.getcwd()
      else:
        cwd = {False: os.path.dirname(sys.argv[0]),
                True:                 sys.argv[0]}[os.path.isdir(sys.argv[0])]
      damask_root = os.path.normpath(os.path.join(os.path.realpath(cwd),self.rootRelation))

    return damask_root

  def binDir(self):
    damask_bin  = os.getenv('DAMASK_BIN')
    if damask_bin  == '' or damask_bin  == None: damask_bin = self.relPath('bin/')
    return damask_bin
    
  def get_pathInfo(self):
    try:                                                    # check for user-defined pathinfo
      file = open(self.relPath('lib/pathinfo'))
      content = file.readlines()
      file.close()
      for line in content:
        self.pathInfo[line.split()[0].lower()] = os.path.normpath(os.path.join(self.relPath('lib/'),line.split()[1]))
    except:
      pass

