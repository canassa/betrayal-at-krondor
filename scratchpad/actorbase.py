import struct
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
ROSTER=0x131f; SA=0x5f; SI=0x16
gid=sorted({g for enc in range(700) for g in struct.unpack_from('<7h',data,ROSTER+enc*14) if g>0})
def test(AB):
    # frac(+3) and perm(+4) of each stat slot should be 0/small; cParty(0x58)==0 for monsters
    fz=0; ptot=0; cp0=0; n=0
    for g in gid:
        r=data[AB+g*SA:AB+g*SA+SA]
        n+=1
        if r[0x58]==0: cp0+=1
        for j in range(16):
            ptot+=1
            if r[8+j*5+3]==0: fz+=1  # frac==0
    return fz,ptot,cp0,n
for AB in (0x90e7,0x90f3):
    fz,ptot,cp0,n=test(AB)
    print('actor_base=%#x: frac==0 %d/%d (%.1f%%)  cParty==0 %d/%d'%(AB,fz,ptot,100*fz/ptot,cp0,n))
