import struct
data = open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
STRIDE_A=0x5f; N=1730
# For each candidate base near 0x90e7, count records where cParty(off 0x58) in {0} and stats[0].max in 1..250
best=[]
for base in range(0x90e7-40, 0x90e7+40):
    party0=0; healthok=0
    for i in range(200):
        off=base+i*STRIDE_A
        rec=data[off:off+STRIDE_A]
        if len(rec)<STRIDE_A: break
        if rec[0x58]==0: party0+=1
        h=rec[0x08]  # health max
        if 1<=h<=250: healthok+=1
    best.append((party0+healthok, base, party0, healthok))
best.sort(reverse=True)
for s,b,p,h in best[:8]:
    print('base=%#x score=%d party0=%d healthok=%d'%(b,s,p,h))
