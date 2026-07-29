import struct
from collections import Counter
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
SI=0x16; N=1730
# For candidate inner bases, count records where short@+2 in valid monster range (1..0x40) and high byte 0
def score(IB):
    good=0; nz=0
    for i in range(N):
        ir=data[IB+i*SI:IB+i*SI+SI]
        if not any(ir): continue
        nz+=1
        v=struct.unpack_from('<H',ir,2)[0]
        if 1<=v<=0x40: good+=1
    return good,nz
best=[]
for IB in range(0x312e5-8,0x312e5+40):
    g,nz=score(IB)
    best.append((g,IB,nz))
best.sort(reverse=True)
for g,ib,nz in best[:8]:
    print('inner_base=%#x good_classid=%d nz=%d'%(ib,g,nz))
