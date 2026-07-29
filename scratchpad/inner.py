import struct
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
IB=0x312e5; SI=0x16; N=1730
# dump first 12 nonzero inner records raw hex
shown=0
for i in range(N):
    ir=data[IB+i*SI:IB+i*SI+SI]
    if not any(ir): continue
    print('inner %4d: %s'%(i, ir.hex(' ')))
    shown+=1
    if shown>=12: break
print()
# how many inners are entirely zero?
zero=sum(1 for i in range(N) if not any(data[IB+i*SI:IB+i*SI+SI]))
print('zero inners:', zero, 'nonzero:', N-zero)
