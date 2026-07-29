import struct
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
ROSTER=0x131f; AB=0x90e7; SA=0x5f; IB0=0x312e5; SI=0x16
gid=sorted({g for enc in range(700) for g in struct.unpack_from('<7h',data,ROSTER+enc*14) if g>0})
# combatants whose inner (any base) is nonzero -- use gid with nonzero at IB0
nz=[g for g in gid if any(data[IB0+g*SI:IB0+g*SI+SI])]
print('roster gid>0:',len(gid),'nonzero-inner@IB0:',len(nz))
best=[]
for d in range(-20,20):
    IB=IB0+d
    ok=0
    for g in nz:
        v=struct.unpack_from('<H',data,IB+g*SI+2)[0]
        if 1<=v<=0x40: ok+=1
    best.append((ok,d,IB))
best.sort(reverse=True)
for ok,d,ib in best[:6]:
    print('delta %+3d base %#x: classid@2 valid=%d/%d'%(d,ib,ok,len(nz)))
# also check: does actor pool have class-id-like data? sweep actor for a monster-type field
