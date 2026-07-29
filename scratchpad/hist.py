import struct
from collections import Counter
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
IB=0x312e5; SI=0x16; N=1730
cols=[Counter() for _ in range(SI)]
recs=[]
for i in range(N):
    ir=data[IB+i*SI:IB+i*SI+SI]
    if not any(ir): continue
    recs.append(ir)
    for o in range(SI):
        cols[o][ir[o]]+=1
print('nonzero inner recs:', len(recs))
for o in range(SI):
    top=cols[o].most_common(4)
    distinct=len(cols[o])
    print('off 0x%02x: distinct=%3d top=%s'%(o,distinct,top))
