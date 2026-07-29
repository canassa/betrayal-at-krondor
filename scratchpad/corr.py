import struct
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
ROSTER=0x131f; AB=0x90e7; SA=0x5f; IB0=0x312e5; SI=0x16
# gather roster gidx>0
gid=set()
for enc in range(700):
    r=struct.unpack_from('<7h', data, ROSTER+enc*14)
    for g in r:
        if g>0: gid.add(g)
gid=sorted(gid)
# combatants with actor.health.max>0
live=[g for g in gid if data[AB+g*SA+8]>0]
print('roster gidx>0:',len(gid),'with health>0:',len(live))
# sweep IB delta, count how many live combatants have inner classid@2 in 1..0x40
for d in range(-4,20):
    IB=IB0+d
    ok=0
    for g in live:
        v=struct.unpack_from('<H',data,IB+g*SI+2)[0]
        if 1<=v<=0x40: ok+=1
    print('IB delta %+3d (base %#x): classid_valid=%d/%d'%(d,IB,ok,len(live)))
