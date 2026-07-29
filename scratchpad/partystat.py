import struct
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
BASE=0xdb; SA=0x5f
SKILL=["Health","Stamina","Speed","Strength","Defense","Xbow","Melee","Cast","Assess","Armor","Weapon","Barding","Haggle","Lock","Scout","Stealth"]
names=["Locklear","Gorath","Owyn","(empty)","James","Patrus"]
for i in range(6):
    off=BASE+i*SA
    r=data[off:off+SA]
    nameptr=struct.unpack_from('<H',r,0)[0]
    spells=struct.unpack_from('<3H',r,2)
    cParty=r[0x58]
    inner=struct.unpack_from('<H',r,0x5d)[0]
    print('char %d %-8s @%#x: name_ptr=%#06x spells=%s cParty=%d inner_ptr=%#06x'%(i,names[i],off,nameptr,tuple(hex(s) for s in spells),cParty,inner))
    line=[]
    for j in range(16):
        mx,ba,ca,fr,pm=r[8+j*5:8+j*5+5]
        if mx or ba: line.append('%s=%d/%d'%(SKILL[j],ba,mx))
    print('   ',', '.join(line))
