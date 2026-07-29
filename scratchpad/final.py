import struct
from collections import Counter
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
ROSTER=0x131f; AB=0x90e7; SA=0x5f; IB=0x312f1; SI=0x16
gid=sorted({g for enc in range(700) for g in struct.unpack_from('<7h',data,ROSTER+enc*14) if g>0})
# boundary dump
print('boundary 0x312e0..0x31300:', data[0x312e0:0x31300].hex(' '))
print()
# validate inner fields for roster combatants
cid=Counter(); grid=Counter(); flags=Counter(); shead=Counter(); morale=Counter()
for g in gid:
    ir=data[IB+g*SI:IB+g*SI+SI]
    if not any(ir): continue
    cid[struct.unpack_from('<H',ir,2)[0]]+=1
    grid[(ir[4],ir[5])]+=1
    flags[ir[8]]+=1
    shead[struct.unpack_from('<h',ir,0x0a)[0]]+=1
    morale[struct.unpack_from('b',ir[0x0e:0x0f])[0]]+=1
print('class_id@2 top:', cid.most_common(12))
print('flags@8 top:', flags.most_common(6))
print('status_head@0a top:', shead.most_common(4))
print('morale@0e top:', morale.most_common(8))
print('grid(x@4,y@5) sample:', grid.most_common(5))
# sample a few full records
for g in gid[3:8]:
    ir=data[IB+g*SI:IB+g*SI+SI]
    print('gid %4d: %s  class_id=%d gx=%d gy=%d flags=%02x'%(g,ir.hex(' '),struct.unpack_from('<H',ir,2)[0],ir[4],ir[5],ir[8]))
