import struct
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
ROSTER=0x131f; AB=0x90e7; SA=0x5f; IB=0x312e5; SI=0x16
def rd(o,n): return data[o:o+n]
# scan 700 rosters, collect gidx values referenced
gidxs=[]
for enc in range(700):
    r=struct.unpack_from('<7h', data, ROSTER+enc*14)
    for slot,g in enumerate(r):
        if g!=-1:
            gidxs.append((enc,slot,g))
print('total roster refs (real combatants):', len(gidxs))
print('max gidx:', max(g for _,_,g in gidxs), 'min:', min(g for _,_,g in gidxs))
# examine first 8 referenced combatants
for enc,slot,g in gidxs[:8]:
    ar=data[AB+g*SA:AB+g*SA+SA]
    ir=data[IB+g*SI:IB+g*SI+SI]
    classid=struct.unpack_from('<h',ir,2)[0]
    health=ar[8]
    print('enc %3d slot %d gidx %4d: actor.health.max=%3d cParty=%02x | inner=%s classid@2=%d'%(
        enc,slot,g,health,ar[0x58], ir.hex(' '), classid))
