import struct
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
ROSTER=0x131f; AB=0x90e7; SA=0x5f; IB=0x312e5; SI=0x16
gidxs=[]
for enc in range(700):
    r=struct.unpack_from('<7h', data, ROSTER+enc*14)
    for slot,g in enumerate(r):
        if g>0: gidxs.append((enc,slot,g))
distinct=sorted(set(g for _,_,g in gidxs))
print('roster refs with g>0:', len(gidxs), 'distinct nonzero gidx:', len(distinct))
print('distinct range', distinct[0], '..', distinct[-1])
for enc,slot,g in gidxs[:10]:
    ar=data[AB+g*SA:AB+g*SA+SA]
    ir=data[IB+g*SI:IB+g*SI+SI]
    c2=struct.unpack_from('<h',ir,2)[0]; ce=struct.unpack_from('<h',ir,0x0e)[0]
    print('enc %3d slot %d gidx %4d: h.max=%3d cParty=%02x classid@2=%d classid@0e=%d inner=%s'%(
        enc,slot,g,ar[8],ar[0x58],c2,ce,ir.hex(' ')))
