import struct
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
AB=0x90e7; SA=0x5f; IB=0x312e5; SI=0x16; N=1730
from collections import Counter
c58=Counter(); frac=Counter(); perm=Counter()
for i in range(N):
    r=data[AB+i*SA:AB+i*SA+SA]
    if not any(r): continue
    c58[r[0x58]]+=1
    for j in range(16):
        frac[r[8+j*5+3]]+=1
        perm[r[8+j*5+4]]+=1
print('offset0x58 (cParty) distribution:', c58.most_common(8))
print('stat frac byte distribution:', frac.most_common(5))
print('stat perm byte distribution:', perm.most_common(5))
# tail bytes of first 8 nonempty records
shown=0
for i in range(N):
    r=data[AB+i*SA:AB+i*SA+SA]
    if not any(r): continue
    tail=r[0x58:0x5f]
    print('rec %d: cParty=%02x actor_rec=%02x%02x:%02x%02x inner=%02x%02x  health(max,base)=%d,%d'%(
        i, r[0x58], r[0x5c],r[0x5b],r[0x5a],r[0x59], r[0x5e],r[0x5d], r[8],r[9]))
    shown+=1
    if shown>=8: break
# inner region: class_id distribution
cid=Counter()
for i in range(N):
    ir=data[IB+i*SI:IB+i*SI+SI]
    cid[struct.unpack_from('<h',ir,2)[0]]+=1
print('inner class_id top:', cid.most_common(12))
