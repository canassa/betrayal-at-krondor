import sys
sys.path.insert(0,'cli/src')
from bakbuild import omf
obj = omf.parse('work/ref/CBENC.OBJ')
for seg in obj.segments:
    print('SEG', seg.name)
for p in obj.publics:
    seg=obj.segments[p.segment_idx-1].name
    print('%-8s %#06x %s'%(seg,p.offset,p.name))
