import sys
sys.path.insert(0,'cli/src')
from bakbuild import omf
obj = omf.parse('work/ref/CBENC.OBJ')
for p in sorted(obj.publics,key=lambda x:x.offset):
    if obj.segments[p.segment_idx-1].name.endswith('TEXT'):
        print('%#06x %s'%(p.offset,p.name))
