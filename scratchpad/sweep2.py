import struct
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
STRIDE_A=0x5f
def score(base, n=1730):
    good=0; nonempty=0
    for i in range(n):
        off=base+i*STRIDE_A
        rec=data[off:off+STRIDE_A]
        if len(rec)<STRIDE_A: break
        stats=rec[0x08:0x08+80]
        # nonempty if health max>0
        if stats[0]==0: 
            # empty record: all stats zero?
            if any(stats): pass
            else: 
                good+=1; continue
        nonempty+=1
        ok=all(stats[j*5+0] >= stats[j*5+1] for j in range(16))  # max>=base
        # cached (idx2) should equal base or max
        if ok: good+=1
    return good
res=[]
for base in range(0x90e7-30,0x90e7+30):
    res.append((score(base),base))
res.sort(reverse=True)
for s,b in res[:6]:
    print('base=%#x good=%d'%(b,s))
